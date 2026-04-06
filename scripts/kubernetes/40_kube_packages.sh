#!/usr/bin/env bash
set -euo pipefail

echo "[K8S] Kubernetes repository en pakketten installeren..."
apt-get -y install apt-transport-https ca-certificates curl gpg

install -d -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' > /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get -y install kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

echo "[K8S] Kubernetes tools (kubeadm/kubelet/kubectl) geïnstalleerd."
