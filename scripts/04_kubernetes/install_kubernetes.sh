#!/usr/bin/env bash
set -euo pipefail

K8S_CHANNEL="${K8S_CHANNEL:-v1.30}"

install_containerd() {
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y containerd
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y containerd
  elif command -v yum >/dev/null 2>&1; then
    yum install -y containerd
  else
    echo "Geen ondersteunde package manager gevonden voor containerd." >&2
    exit 1
  fi

  mkdir -p /etc/containerd
  containerd config default > /etc/containerd/config.toml
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

  systemctl enable --now containerd
  systemctl restart containerd
}

configure_k8s_prereqs() {
  cat > /etc/modules-load.d/k8s.conf <<'MODS'
overlay
br_netfilter
MODS

  modprobe overlay
  modprobe br_netfilter

  cat > /etc/sysctl.d/99-kubernetes-cri.conf <<'SYSCTL'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
SYSCTL
  sysctl --system >/dev/null

  swapoff -a
  sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab || true
}

install_kubernetes_tools() {
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y apt-transport-https ca-certificates curl gpg

    mkdir -p /etc/apt/keyrings
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_CHANNEL}/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_CHANNEL}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list

    apt-get update -y
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
  elif command -v dnf >/dev/null 2>&1; then
    cat > /etc/yum.repos.d/kubernetes.repo <<REPO
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${K8S_CHANNEL}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${K8S_CHANNEL}/rpm/repodata/repomd.xml.key
REPO

    dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
  elif command -v yum >/dev/null 2>&1; then
    cat > /etc/yum.repos.d/kubernetes.repo <<REPO
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${K8S_CHANNEL}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${K8S_CHANNEL}/rpm/repodata/repomd.xml.key
REPO

    yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
  else
    echo "Geen ondersteunde package manager gevonden voor kubeadm/kubelet/kubectl." >&2
    exit 1
  fi

  mkdir -p /etc/default
  cat > /etc/default/kubelet <<'KUBELET'
KUBELET_EXTRA_ARGS=--cgroup-driver=systemd
KUBELET

  systemctl enable --now kubelet
}

install_containerd
configure_k8s_prereqs
install_kubernetes_tools

echo "Containerd en Kubernetes tools installatie gereed."
echo "Geïnstalleerd: containerd, kubeadm, kubelet, kubectl"
