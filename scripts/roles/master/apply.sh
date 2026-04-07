#!/usr/bin/env bash
set -euo pipefail

ROLE_NAME="master"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${TARGET_HOSTNAME:-}" ]]; then
  echo "[ROLE:${ROLE_NAME}] FOUT: TARGET_HOSTNAME is niet gezet." >&2
  exit 1
fi

echo "[ROLE:${ROLE_NAME}] Hostnaam instellen op ${TARGET_HOSTNAME}..."
hostnamectl set-hostname "${TARGET_HOSTNAME}"
echo "${ROLE_NAME}" > /etc/server-role

bash "${SCRIPT_DIR}/firewall.sh"

echo "[ROLE:${ROLE_NAME}] Basisrol toegepast."
