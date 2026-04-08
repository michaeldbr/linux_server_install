#!/usr/bin/env bash
set -euo pipefail

ROLE_NAME="${1:-}"
CONTROL_PLANE_ENDPOINT="${2:-}"

if [[ -z "${ROLE_NAME}" ]]; then
  echo "[SERVICES] FOUT: role argument ontbreekt." >&2
  exit 1
fi

if [[ -z "${CONTROL_PLANE_ENDPOINT}" ]]; then
  echo "[SERVICES] FOUT: control plane endpoint ontbreekt." >&2
  exit 1
fi

echo "[SERVICES:${ROLE_NAME}] keepalived + haproxy installeren..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y keepalived haproxy

install -d -m 0755 /etc/linux-server-install
cat > /etc/linux-server-install/control-plane-endpoint <<CFG
CONTROL_PLANE_ENDPOINT=${CONTROL_PLANE_ENDPOINT}
CFG
chmod 0644 /etc/linux-server-install/control-plane-endpoint

echo "[SERVICES:${ROLE_NAME}] Endpoint vastgelegd op ${CONTROL_PLANE_ENDPOINT}."
echo "[SERVICES:${ROLE_NAME}] Klaar."
