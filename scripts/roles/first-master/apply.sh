#!/usr/bin/env bash
set -euo pipefail

ROLE_NAME="first-master"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONTROL_PLANE_ENDPOINT="${CONTROL_PLANE_ENDPOINT:-10.0.0.100}"
HAPROXY_BIND_PORT="${HAPROXY_BIND_PORT:-7443}"
POD_NETWORK_CIDR="${POD_NETWORK_CIDR:-10.244.0.0/16}"

if [[ -z "${CONTROL_PLANE_ENDPOINT:-}" ]]; then
  echo "[ROLE:${ROLE_NAME}] FOUT: CONTROL_PLANE_ENDPOINT is niet gezet." >&2
  exit 1
fi

if [[ -z "${TARGET_HOSTNAME:-}" ]]; then
  echo "[ROLE:${ROLE_NAME}] FOUT: TARGET_HOSTNAME is niet gezet." >&2
  exit 1
fi

echo "[ROLE:${ROLE_NAME}] Hostnaam instellen op ${TARGET_HOSTNAME}..."
hostnamectl set-hostname "${TARGET_HOSTNAME}"
echo "${ROLE_NAME}" > /etc/server-role

bash "${SCRIPT_DIR}/firewall.sh"
bash "${SCRIPT_DIR}/../../services/install_control_plane_lb.sh" "${ROLE_NAME}" "${CONTROL_PLANE_ENDPOINT}"

if [[ ! -f /etc/kubernetes/admin.conf ]]; then
  ADVERTISE_ADDRESS="${WIREGUARD_SERVER_IP:-}"
  if [[ -z "${ADVERTISE_ADDRESS}" ]]; then
    ADVERTISE_ADDRESS="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi

  if [[ -z "${ADVERTISE_ADDRESS}" ]]; then
    echo "[ROLE:${ROLE_NAME}] FOUT: kon advertise address niet bepalen voor kubeadm init." >&2
    exit 1
  fi

  echo "[ROLE:${ROLE_NAME}] kubeadm init uitvoeren (eerste control-plane)..."
  kubeadm init \
    --control-plane-endpoint "${CONTROL_PLANE_ENDPOINT}:${HAPROXY_BIND_PORT}" \
    --apiserver-advertise-address "${ADVERTISE_ADDRESS}" \
    --pod-network-cidr "${POD_NETWORK_CIDR}"

  mkdir -p /root/.kube
  cp /etc/kubernetes/admin.conf /root/.kube/config
  chown root:root /root/.kube/config

  echo "[ROLE:${ROLE_NAME}] kubeadm init afgerond."
else
  echo "[ROLE:${ROLE_NAME}] /etc/kubernetes/admin.conf bestaat al, kubeadm init overslaan."
fi

echo "[ROLE:${ROLE_NAME}] Basisrol toegepast met control plane endpoint ${CONTROL_PLANE_ENDPOINT}."
