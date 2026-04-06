#!/usr/bin/env bash
set -euo pipefail

echo "[K8S] Containerd installeren en configureren..."
apt-get -y install containerd

install -d -m 755 /etc/containerd
if [[ ! -f /etc/containerd/config.toml ]]; then
  containerd config default > /etc/containerd/config.toml
fi

sed -i 's/^\s*SystemdCgroup\s*=\s*false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl daemon-reload
systemctl enable containerd
systemctl restart containerd

if [[ ! -S /run/containerd/containerd.sock ]]; then
  echo "[K8S] FOUT: containerd socket ontbreekt (/run/containerd/containerd.sock)." >&2
  exit 1
fi

echo "[K8S] Containerd klaar."
