#!/bin/bash
set -e

MASTER="k8s-master"

echo "[+] Verifying Istio components inside $MASTER ..."

multipass exec $MASTER -- bash -c "
  echo '[+] Checking Istio control plane:'
  kubectl get pods -n istio-system

  echo '[+] Checking Istio services:'
  kubectl get svc -n istio-system

  echo '[+] Checking sidecar injection labels:'
  kubectl get namespace -L istio-injection
"

echo "[✔] Verification complete."
