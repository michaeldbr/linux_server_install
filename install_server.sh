#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/scripts/common.sh"

if [[ ${EUID} -ne 0 ]]; then
  echo "Dit script moet als root worden uitgevoerd (bijv. met sudo)." >&2
  exit 1
fi

echo "[1/8] Systeem pakketlijsten verversen en updates installeren..."
"${SCRIPT_DIR}/scripts/10_system_update.sh"

echo "[2/8] OpenSSH server en firewall pakketten installeren..."
"${SCRIPT_DIR}/scripts/20_install_ssh_and_firewall_packages.sh"

echo "[3/8] Gebruiker '${MICHAEL_USER}' configureren..."
"${SCRIPT_DIR}/scripts/30_configure_michael_user.sh"

echo "[4/8] Root login uitschakelen en SSH hardenen..."
"${SCRIPT_DIR}/scripts/40_harden_ssh.sh"

echo "[5/8] Firewall regels met chain 'ip' instellen..."
"${SCRIPT_DIR}/scripts/50_configure_firewall.sh"

echo "[6/8] Opschonen van ongebruikte pakketten..."
"${SCRIPT_DIR}/scripts/60_cleanup.sh"

echo "[7/8] Configuratiecontrole sudoers..."
visudo -cf "/etc/sudoers.d/${MICHAEL_USER}"

echo "[8/8] Klaar. SSH draait op poort ${SSH_PORT}."
