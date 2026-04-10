#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HAPROXY_SCRIPT="${BASE_DIR}/install_haproxy.sh"

if [[ ! -x "$HAPROXY_SCRIPT" ]]; then
  echo "HAProxy script ontbreekt of is niet uitvoerbaar: $HAPROXY_SCRIPT" >&2
  exit 1
fi

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

check_api_server() {
  if [[ ! -f /etc/kubernetes/admin.conf ]]; then
    return 0
  fi

  echo "Controle API server..."

  if ! su - michael -c "kubectl get nodes" >/dev/null 2>&1; then
    echo "API server niet bereikbaar!" >&2
    exit 1
  fi
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

"$HAPROXY_SCRIPT"
run_kubeadm_init_if_first_master
post_init_setup
check_api_server

echo "Master setup voltooid: HAProxy + (optioneel) kubeadm init + kubeconfig/Flannel + API check."
