#!/bin/bash
# ==============================================================================
# teardown.sh
# Stops and deletes all Kubernetes VMs created via multipass-init.sh
# ==============================================================================

set -e

declare -a VMS=("k8s-master" "k8s-worker1" "k8s-worker2")

echo "[+] Stopping and deleting VMs..."
for vm in "${VMS[@]}"; do
  if multipass info "${vm}" &>/dev/null; then
    echo "    -> Removing ${vm}"
    multipass stop "${vm}" || true
    multipass delete --purge "${vm}" || true
  fi
done

echo "[+] Cleaning old IP file..."
rm -f vm_ips.sh || true

echo "[✔] Teardown complete."
