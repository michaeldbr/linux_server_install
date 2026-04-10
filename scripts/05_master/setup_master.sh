#!/usr/bin/env bash
set -euo pipefail

if [[ -f /etc/kubernetes/admin.conf ]]; then
  echo "Kubernetes master lijkt al geinitialiseerd (/etc/kubernetes/admin.conf bestaat al)."
else
  echo "Start kubeadm init..."
  kubeadm init
  echo "kubeadm init voltooid."
fi

echo "Kubeconfig instellen voor user michael..."
mkdir -p /home/michael/.kube
cp /etc/kubernetes/admin.conf /home/michael/.kube/config
chown -R michael:michael /home/michael/.kube

echo "CNI (Flannel) installeren..."
su - michael -c "kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml"

echo "Wachten tot nodes Ready zijn..."
su - michael -c "kubectl wait --for=condition=Ready node --all --timeout=120s"

echo "Master setup voltooid: kubeconfig + Flannel + Ready check."
