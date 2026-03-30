#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/00_common/common.sh
source "${SCRIPT_DIR}/scripts/00_common/common.sh"

if [[ ${EUID} -ne 0 ]]; then
  echo "Dit script moet als root worden uitgevoerd (bijv. met sudo)." >&2
  exit 1
fi

echo "[1/7] Systeem pakketlijsten verversen en updates installeren..."
"${SCRIPT_DIR}/scripts/01_system/01_system_update.sh"

echo "[2/7] SSH pakketten installeren..."
"${SCRIPT_DIR}/scripts/02_ssh/02_install_ssh_packages.sh"

echo "[3/7] Gebruiker '${MICHAEL_USER}' configureren..."
"${SCRIPT_DIR}/scripts/02_ssh/03_configure_michael_user.sh"

echo "[4/7] Root login uitschakelen en SSH hardenen..."
"${SCRIPT_DIR}/scripts/02_ssh/04_harden_ssh.sh"

echo "[5/7] Firewall pakketten installeren..."
"${SCRIPT_DIR}/scripts/03_firewall/05_install_firewall_packages.sh"

echo "[6/7] Firewall regels met chain 'ip' instellen..."
"${SCRIPT_DIR}/scripts/03_firewall/06_configure_firewall.sh"

echo "[7/7] Opschonen van ongebruikte pakketten..."
"${SCRIPT_DIR}/scripts/04_system/07_cleanup.sh"

echo "Klaar. SSH draait op poort ${SSH_PORT}."
