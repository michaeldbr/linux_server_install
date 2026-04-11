#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f /etc/kubernetes/admin.conf ]]; then
  echo "Geen admin.conf gevonden; etcd/quorum check overgeslagen."
  exit 0
fi

export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl get endpoints kube-apiserver -n default
kubectl get componentstatuses || true

echo "etcd/control-plane basischeck uitgevoerd."
