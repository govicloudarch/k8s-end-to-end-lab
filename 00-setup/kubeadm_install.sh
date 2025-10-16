#!/bin/bash
# ==============================================================================
# kubeadm_install.sh (comprehensive)
# Bootstraps a minimal multi-node Kubernetes cluster via kubeadm on Multipass.
# Prereq: Run multipass-init.sh first (this creates vm_ips.sh).
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# Load IPs exported by multipass-init.sh (vm_ips.sh must set k8s_master_IP and k8s_worker1_IP)
if [ ! -f ./vm_ips.sh ]; then
  echo "ERROR: vm_ips.sh not found. Run multipass-init.sh first."
  exit 1
fi
# shellcheck disable=SC1091
source ./vm_ips.sh

MASTER="k8s-master"
WORKER="k8s-worker1"
MASTER_IP="${k8s_master_IP:-}"
WORKER_IP="${k8s_worker1_IP:-}"

if [ -z "$MASTER_IP" ]; then
  echo "ERROR: k8s_master_IP not set in vm_ips.sh"
  exit 1
fi

echo "[+] Prepping nodes (kernel modules + sysctls) on ${MASTER} and ${WORKER}..."
for node in "${MASTER}" "${WORKER}"; do
  multipass exec "${node}" -- bash -c "
    set -e
    sudo modprobe br_netfilter || true
    echo 'br_netfilter' | sudo tee /etc/modules-load.d/br_netfilter.conf >/dev/null
    # Ensure k8s-friendly sysctls
    echo 'net.bridge.bridge-nf-call-iptables=1' | sudo tee /etc/sysctl.d/99-k8s.conf >/dev/null
    echo 'net.bridge.bridge-nf-call-ip6tables=1' | sudo tee -a /etc/sysctl.d/99-k8s.conf >/dev/null
    echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.d/99-k8s.conf >/dev/null
    sudo sysctl --system
  "
done

echo "[+] Installing Kubernetes packages and containerd on all nodes..."
install_kube_packages() {
  local node="$1"
  multipass exec "${node}" -- bash -c "
    set -e
    sudo apt-get update -y
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/trusted.gpg.d/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update -y
    sudo apt-get install -y kubelet kubeadm kubectl containerd conntrack
    sudo apt-mark hold kubelet kubeadm kubectl containerd

    sudo mkdir -p /etc/containerd
    sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml || true
    sudo systemctl restart containerd
    sudo systemctl enable containerd
  "
}

install_kube_packages "${MASTER}"
install_kube_packages "${WORKER}"

echo "[+] Initializing control plane on ${MASTER} (advertise ${MASTER_IP})..."
# use advertise address explicitly so apiserver binds correct IP
multipass exec "${MASTER}" -- sudo bash -c "kubeadm init --apiserver-advertise-address=${MASTER_IP} --pod-network-cidr=10.244.0.0/16" | tee kubeadm-init.out

echo "[+] Setting up kubeconfig inside master VM for ubuntu user..."
multipass exec "${MASTER}" -- bash -c "
  sudo mkdir -p /home/ubuntu/.kube
  sudo cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
  sudo chown ubuntu:ubuntu /home/ubuntu/.kube/config
"

echo "[+] Copying kubeconfig to host ~/.kube/config"
multipass exec "${MASTER}" -- sudo cat /etc/kubernetes/admin.conf | tee kubeconfig >/dev/null
mkdir -p ~/.kube
cp kubeconfig ~/.kube/config
chmod 600 ~/.kube/config

# Wait for kube-apiserver HTTPS on the node IP (use MASTER_IP not 127.0.0.1)
echo "[+] Waiting for kube-apiserver HTTPS at ${MASTER_IP}:6443 ..."
multipass exec "${MASTER}" -- bash -c "
  for i in \$(seq 1 60); do
    if sudo curl --cacert /etc/kubernetes/pki/ca.crt -sSf https://${MASTER_IP}:6443/healthz >/dev/null 2>&1; then
      echo '    -> API server HTTPS OK'
      exit 0
    fi
    echo '    -> waiting for API server... ('\$i'/60)'
    sleep 3
  done
  echo '    -> timed out waiting for API server' >&2
  exit 1
"

echo "[+] Ensuring control-plane deployments are available (kube-system)..."
multipass exec "${MASTER}" -- bash -c "
  export KUBECONFIG=/home/ubuntu/.kube/config
  kubectl wait --for=condition=Available --timeout=180s deployment --all -n kube-system || true
"

echo "[+] Deploying Flannel CNI (and waiting for its pods)..."
multipass exec "${MASTER}" -- bash -c "
  export KUBECONFIG=/home/ubuntu/.kube/config
  kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
"

# Add local-path-provisioner for dynamic storage
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Wait for flannel daemonset pods
echo "[+] Waiting for Flannel pods to be Ready..."
multipass exec "${MASTER}" -- bash -c "
  export KUBECONFIG=/home/ubuntu/.kube/config
  kubectl -n kube-flannel wait --for=condition=Ready pods --all --timeout=180s || true
"

# Ensure kernel modules/sysctls are set on the worker too (redundant but safe)
echo "[+] Re-applying kernel module/sysctl checks on worker..."
multipass exec "${WORKER}" -- bash -c "
  sudo modprobe br_netfilter || true
  echo 'br_netfilter' | sudo tee /etc/modules-load.d/br_netfilter.conf >/dev/null
  echo 'net.bridge.bridge-nf-call-iptables=1' | sudo tee /etc/sysctl.d/99-k8s.conf >/dev/null
  echo 'net.bridge.bridge-nf-call-ip6tables=1' | sudo tee -a /etc/sysctl.d/99-k8s.conf >/dev/null
  sudo sysctl --system
"

# Now that CNI is applied, generate join command and join worker
echo "[+] Generating join command (after CNI ready)..."
JOIN_CMD=$(multipass exec "${MASTER}" -- bash -c "export KUBECONFIG=/home/ubuntu/.kube/config && sudo kubeadm token create --print-join-command")

echo "[+] Joining worker node ${WORKER}..."
multipass exec "${WORKER}" -- sudo bash -c "${JOIN_CMD}"

echo "[+] Waiting for all nodes to become Ready..."
multipass exec "${MASTER}" -- bash -c "
  export KUBECONFIG=/home/ubuntu/.kube/config
  kubectl wait --for=condition=Ready nodes --all --timeout=180s || true
  kubectl get nodes -o wide
  kubectl get pods -n kube-system -o wide
"


echo "[✔] Cluster bootstrapped successfully!"
echo "    Run locally: kubectl get nodes"
