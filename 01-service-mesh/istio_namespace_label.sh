#!/bin/bash
set -e

MASTER="k8s-master"
NAMESPACE=${1:-default}

echo "[+] Ensuring namespace '$NAMESPACE' exists..."
multipass exec $MASTER -- bash -c "
  kubectl get namespace $NAMESPACE >/dev/null 2>&1 || kubectl create namespace $NAMESPACE
"

echo "[+] Labeling namespace '$NAMESPACE' for Istio sidecar injection..."
multipass exec $MASTER -- bash -c "
  kubectl label namespace $NAMESPACE istio-injection=enabled --overwrite
  echo
  echo '[+] Current namespace labels:'
  kubectl get namespace -L istio-injection
"

echo "[✔] Namespace '$NAMESPACE' labeled for sidecar injection."
