#!/bin/bash
set -e

VM="k8s-master"
MANIFEST_DIR="/home/ubuntu/manifests"

echo "[+] Copying manifests to $VM..."
multipass transfer --recursive ./manifests $VM:$MANIFEST_DIR

echo "[+] Applying manifests inside $VM..."
multipass exec $VM -- bash -c "
  kubectl apply -f $MANIFEST_DIR/webapp-pvc.yaml &&
  kubectl apply -f $MANIFEST_DIR/webapp-deployment.yaml &&
  kubectl apply -f $MANIFEST_DIR/webapp-service.yaml &&
  kubectl apply -f $MANIFEST_DIR/webapp-gateway.yaml
"
echo "[✔] Webapp deployed inside Kubernetes cluster"

