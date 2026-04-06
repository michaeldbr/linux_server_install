#!/usr/bin/env bash
set -euo pipefail

ROLE_NAME="worker"

if [[ -z "${TARGET_HOSTNAME:-}" ]]; then
  echo "[ROLE:${ROLE_NAME}] FOUT: TARGET_HOSTNAME is niet gezet." >&2
  exit 1
fi

echo "[ROLE:${ROLE_NAME}] Hostnaam instellen op ${TARGET_HOSTNAME}..."
hostnamectl set-hostname "${TARGET_HOSTNAME}"
echo "${ROLE_NAME}" > /etc/server-role

echo "[ROLE:${ROLE_NAME}] Basisrol toegepast."
