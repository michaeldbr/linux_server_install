#!/usr/bin/env bash
set -euo pipefail

install_haproxy_if_needed() {
  if command -v haproxy >/dev/null 2>&1; then
    return 0
  fi

  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y haproxy
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y haproxy
  elif command -v yum >/dev/null 2>&1; then
    yum install -y haproxy
  else
    echo "Geen ondersteunde package manager gevonden voor HAProxy." >&2
    exit 1
  fi
}

configure_hosts() {
  if ! grep -qE '^127\.0\.0\.1[[:space:]]+k8s-api\.internal(\s|$)' /etc/hosts; then
    echo "127.0.0.1 k8s-api.internal" >> /etc/hosts
  fi
}

configure_haproxy() {
  cat > /etc/haproxy/haproxy.cfg <<'CFG'
global
  log /dev/log local0
  log /dev/log local1 notice
  daemon

defaults
  log global
  mode tcp
  option dontlognull
  timeout connect 5s
  timeout client 50s
  timeout server 50s

frontend k8s
  bind 127.0.0.1:6443
  mode tcp
  default_backend masters

backend masters
  mode tcp
  option tcp-check
  server master1 10.0.0.1:6443 check
  server master2 10.0.0.2:6443 check
  server master3 10.0.0.3:6443 check
CFG

  systemctl enable --now haproxy
  systemctl restart haproxy
}

run_kubeadm_init_if_first_master() {
  if [[ "${FIRST_MASTER:-nee}" != "ja" ]]; then
    echo "Dit is geen eerste master; kubeadm init wordt overgeslagen."
    return 0
  fi

  if [[ -z "${INTERNAL_IP:-}" ]]; then
    echo "INTERNAL_IP ontbreekt voor kubeadm init." >&2
    exit 1
  fi

  if [[ -f /etc/kubernetes/admin.conf ]]; then
    echo "Kubernetes master lijkt al geinitialiseerd (/etc/kubernetes/admin.conf bestaat al)."
    return 0
  fi

  echo "Start kubeadm init met control-plane endpoint k8s-api.internal:6443..."
  kubeadm init \
    --control-plane-endpoint "k8s-api.internal:6443" \
    --apiserver-advertise-address="${INTERNAL_IP}" \
    --pod-network-cidr=10.244.0.0/16

  echo "kubeadm init voltooid."
}

post_init_setup() {
  if [[ ! -f /etc/kubernetes/admin.conf ]]; then
    return 0
  fi

  echo "Kubeconfig instellen voor user michael..."
  mkdir -p /home/michael/.kube
  cp /etc/kubernetes/admin.conf /home/michael/.kube/config
  chown -R michael:michael /home/michael/.kube

  if [[ "${FIRST_MASTER:-nee}" == "ja" ]]; then
    echo "CNI (Flannel) installeren..."
    su - michael -c "kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml"

    echo "Wachten tot nodes Ready zijn..."
    su - michael -c "kubectl wait --for=condition=Ready node --all --timeout=120s"
  fi
}

install_haproxy_if_needed
configure_hosts
configure_haproxy
run_kubeadm_init_if_first_master
post_init_setup

echo "Master setup voltooid: hosts + HAProxy + (optioneel) kubeadm init + kubeconfig/Flannel."
