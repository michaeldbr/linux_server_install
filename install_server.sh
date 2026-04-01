#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/00_common/common.sh
source "${SCRIPT_DIR}/scripts/00_common/common.sh"

if [[ ${EUID} -ne 0 ]]; then
  echo "Dit script moet als root worden uitgevoerd (bijv. met sudo)." >&2
  exit 1
fi

echo "[1/10] Systeem pakketlijsten verversen en updates installeren..."
"${SCRIPT_DIR}/scripts/01_system/01_system_update.sh"

echo "[2/10] Tijd en datum synchroniseren + timezone Europe/Amsterdam instellen..."
"${SCRIPT_DIR}/scripts/01_system/02_set_time_and_timezone.sh"

echo "[3/10] SSH pakketten installeren..."
"${SCRIPT_DIR}/scripts/02_ssh/03_install_ssh_packages.sh"

echo "[4/10] Gebruiker '${MICHAEL_USER}' configureren..."
"${SCRIPT_DIR}/scripts/02_ssh/04_configure_michael_user.sh"

echo "[5/10] Root login uitschakelen en SSH hardenen..."
"${SCRIPT_DIR}/scripts/02_ssh/05_harden_ssh.sh"

echo "[6/10] Firewall pakketten installeren..."
"${SCRIPT_DIR}/scripts/03_firewall/06_install_firewall_packages.sh"

echo "[7/10] Firewall regels met chain 'ip' instellen..."
"${SCRIPT_DIR}/scripts/03_firewall/07_configure_firewall.sh"

echo "[8/10] WireGuard installeren..."
"${SCRIPT_DIR}/scripts/03_firewall/09_install_wireguard.sh"

echo "[9/10] Controleren of alles goed is ingesteld (en zo nodig herstellen)..."
"${SCRIPT_DIR}/scripts/04_system/10_verify_and_repair.sh"

echo "[10/10] Opschonen van ongebruikte pakketten..."
"${SCRIPT_DIR}/scripts/04_system/11_cleanup.sh"

echo "Klaar. SSH draait op poort ${SSH_PORT}. WireGuard luistert op UDP poort ${WIREGUARD_PORT}. Tijdzone staat op Europe/Amsterdam."
