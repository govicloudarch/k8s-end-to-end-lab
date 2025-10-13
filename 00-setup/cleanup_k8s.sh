#!/bin/bash
set -e
echo "[+] Cleaning up Kubernetes setup inside Multipass VMs..."

for node in k8s-master k8s-worker1; do
    echo "    -> Cleaning up $node..."
    multipass exec $node -- bash -c "
        sudo kubeadm reset -f
        sudo systemctl stop kubelet containerd || true
        sudo apt-mark unhold kubelet kubeadm kubectl containerd || true
        sudo apt-get purge -y kubelet kubeadm kubectl containerd cri-tools kubernetes-cni || true
        sudo apt-get autoremove -y
        sudo rm -rf ~/.kube /etc/kubernetes /var/lib/etcd /var/lib/kubelet /etc/cni /opt/cni
        sudo rm -rf /etc/systemd/system/kubelet.service.d
        sudo systemctl daemon-reload
    "
done

echo "[✔] Cleanup complete in all Multipass VMs."
