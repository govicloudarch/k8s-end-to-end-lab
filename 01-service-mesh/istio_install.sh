#!/bin/bash
set -e

MASTER="k8s-master"
ISTIO_VERSION="1.23.2"

echo "[+] Downloading and installing Istio inside $MASTER ..."

multipass exec $MASTER -- bash -c "
  set -e
  cd /tmp
  echo '[+] Downloading Istio $ISTIO_VERSION ...'
  curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh -
  cd istio-$ISTIO_VERSION
  export PATH=\$PWD/bin:\$PATH

  echo '[+] Installing Istio (demo profile)...'
  istioctl install --set profile=demo -y

  echo '[+] Labeling default namespace for sidecar injection...'
  kubectl label namespace default istio-injection=enabled --overwrite

  echo '[+] Istio control plane pods:'
  kubectl get pods -n istio-system
"

echo "[✔] Istio installed on cluster inside $MASTER"
