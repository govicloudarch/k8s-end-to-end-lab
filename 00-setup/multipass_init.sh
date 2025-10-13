#!/bin/bash
# ==============================================================================
# multipass-init.sh
# Creates Ubuntu 20.04 VMs using a pre-downloaded cloud image.
# Sets up SSH access, saves IPs, and verifies connectivity.
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# ---------------- Configuration ----------------
# VM names and sizes
declare -A VMS=(
  ["k8s-master"]="--cpus 2 --memory 4G --disk 20G"
  ["k8s-worker1"]="--cpus 2 --memory 4G --disk 20G"
)

# Ubuntu image details
IMAGE_URL="https://cloud-images.ubuntu.com/releases/focal/release/ubuntu-20.04-server-cloudimg-amd64.img"
IMAGE_FILE="ubuntu-20.04-server-cloudimg-amd64.img"
FULL_IMAGE_PATH="$(pwd)/${IMAGE_FILE}"

# IP export file
IP_FILE="vm_ips.sh"

# ---------------- Functions ----------------

download_image() {
  if [ ! -f "${FULL_IMAGE_PATH}" ]; then
    echo "[+] Downloading Ubuntu Focal cloud image..."
    wget -q --show-progress "${IMAGE_URL}" -O "${FULL_IMAGE_PATH}"
    echo "[+] Download complete."
  else
    echo "[=] Image already exists, skipping download."
  fi
}

cleanup_existing_vms() {
  echo "[+] Cleaning up any existing Multipass VMs..."
  for vm in "${!VMS[@]}"; do
    if multipass info "${vm}" &>/dev/null; then
      echo "    -> Removing ${vm}..."
      multipass stop "${vm}" || true
      multipass delete --purge "${vm}" || true
    fi
  done
}

launch_vms() {
  for vm in "${!VMS[@]}"; do
    if multipass info "${vm}" &>/dev/null; then
      echo "[=] ${vm} already exists, skipping launch."
      continue
    fi
    echo "[+] Launching ${vm}..."
    multipass launch "file://${FULL_IMAGE_PATH}" \
    --name "${vm}" \
    --disk 20G \
    --memory 4G \
    --cpus 2
  done
}

provision_ssh_keys() {
  echo "[+] Provisioning SSH keys..."
  if [ ! -f ~/.ssh/id_rsa.pub ]; then
    echo "[!] No SSH key found at ~/.ssh/id_rsa.pub — generating..."
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
  fi
  PUB_KEY=$(<~/.ssh/id_rsa.pub)
  for vm in "${!VMS[@]}"; do
    echo "    -> Copying key to ${vm}"
    multipass exec "${vm}" -- bash -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '${PUB_KEY}' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
  done
}

write_ips_to_file() {
  echo "[+] Writing VM IPs to ${IP_FILE}..."
  echo "#!/bin/bash" > "${IP_FILE}"
  for vm in "${!VMS[@]}"; do
    ip=$(multipass info "${vm}" | awk '/IPv4:/ {print $2}')
    echo "export ${vm//-/_}_IP=${ip}" >> "${IP_FILE}"
  done
  echo "[=] IPs saved to ${IP_FILE}"
}

verify_connectivity() {
  echo "[+] Verifying connectivity..."
  for vm in "${!VMS[@]}"; do
    ip=$(multipass info "${vm}" | awk '/IPv4:/ {print $2}')
    echo "    -> Pinging ${vm} (${ip})"
    if ping -c2 "$ip" >/dev/null 2>&1; then
      echo "       ✅ Ping successful"
    else
      echo "       ⚠️  Ping failed"
    fi
  done
}

# ---------------- Main ----------------
download_image
cleanup_existing_vms
launch_vms
provision_ssh_keys
write_ips_to_file
verify_connectivity

echo "[✔] All VMs launched and ready."
