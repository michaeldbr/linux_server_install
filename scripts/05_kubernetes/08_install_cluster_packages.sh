#!/usr/bin/env bash
set -euo pipefail

if ! command -v apt-get >/dev/null 2>&1; then
  echo "Alleen Debian/Ubuntu (apt-get) wordt ondersteund voor Kubernetes/HA installatie." >&2
  exit 1
fi

apt-get -y install ca-certificates curl gpg

install -d -m 0755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key" \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 0644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

cat > /etc/apt/sources.list.d/kubernetes.list <<'LIST'
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /
LIST

apt-get update
apt-get -y install haproxy keepalived kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
