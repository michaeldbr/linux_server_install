#!/usr/bin/env bash
set -euo pipefail

ROLE_NAME="first-master"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONTROL_PLANE_ENDPOINT="${WIREGUARD_SERVER_IP}"

if [[ -z "${CONTROL_PLANE_ENDPOINT:-}" ]]; then
  echo "[ROLE:${ROLE_NAME}] FOUT: WIREGUARD_SERVER_IP is niet gezet." >&2
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

echo "[ROLE:${ROLE_NAME}] Basisrol toegepast met control plane endpoint ${CONTROL_PLANE_ENDPOINT}."
