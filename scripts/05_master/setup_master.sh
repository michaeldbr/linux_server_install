#!/usr/bin/env bash
set -euo pipefail

if [[ -f /etc/kubernetes/admin.conf ]]; then
  echo "Kubernetes master lijkt al geinitialiseerd (/etc/kubernetes/admin.conf bestaat al)."
else
  echo "Start kubeadm init..."
  kubeadm init
  echo "kubeadm init voltooid."
fi

mkdir -p /home/michael/.kube
cp /etc/kubernetes/admin.conf /home/michael/.kube/config
chown -R michael:michael /home/michael/.kube

export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

echo "Kubeconfig voor michael gezet en Flannel toegepast."
