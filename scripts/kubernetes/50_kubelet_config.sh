#!/usr/bin/env bash
set -euo pipefail

echo "[K8S] Kubelet runtime-endpoint configureren..."

install -d -m 755 /etc/default

if [[ -f /etc/default/kubelet ]]; then
  if grep -q '^KUBELET_EXTRA_ARGS=' /etc/default/kubelet; then
    sed -i 's#^KUBELET_EXTRA_ARGS=.*#KUBELET_EXTRA_ARGS="--container-runtime-endpoint=unix:///run/containerd/containerd.sock"#' /etc/default/kubelet
  else
    printf '\nKUBELET_EXTRA_ARGS="--container-runtime-endpoint=unix:///run/containerd/containerd.sock"\n' >> /etc/default/kubelet
  fi
else
  cat > /etc/default/kubelet <<'CONF'
KUBELET_EXTRA_ARGS="--container-runtime-endpoint=unix:///run/containerd/containerd.sock"
CONF
fi

systemctl daemon-reload
systemctl enable kubelet

echo "[K8S] Kubelet basisconfiguratie klaar (enabled, niet gestart door cluster init)."
