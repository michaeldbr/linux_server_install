#!/usr/bin/env bash
set -euo pipefail

if [[ -f /etc/kubernetes/admin.conf ]]; then
  echo "Kubernetes master lijkt al geinitialiseerd (/etc/kubernetes/admin.conf bestaat al)."
  exit 0
fi

echo "Start kubeadm init..."
kubeadm init

echo "kubeadm init voltooid."
