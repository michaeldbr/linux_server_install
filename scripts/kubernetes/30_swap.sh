#!/usr/bin/env bash
set -euo pipefail

echo "[K8S] Swap uitschakelen..."
swapoff -a || true

if [[ -f /etc/fstab ]]; then
  cp /etc/fstab /etc/fstab.bak
  sed -i '/\sswap\s/s/^/#/' /etc/fstab
fi

echo "[K8S] Swap uitgeschakeld en fstab bijgewerkt."
