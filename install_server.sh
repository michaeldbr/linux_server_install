#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/00_common/common.sh
source "${SCRIPT_DIR}/scripts/00_common/common.sh"

if [[ ${EUID} -ne 0 ]]; then
  echo "Dit script moet als root worden uitgevoerd (bijv. met sudo)." >&2
  exit 1
fi

echo "[INIT] Shell scripts uitvoerbaar maken..."
find "${SCRIPT_DIR}/scripts" -type f -name '*.sh' -exec chmod +x {} +

echo "[1/11] Systeem pakketlijsten verversen en updates installeren..."
bash "${SCRIPT_DIR}/scripts/01_system/01_system_update.sh"

echo "[2/11] Tijd en datum synchroniseren + timezone Europe/Amsterdam instellen..."
bash "${SCRIPT_DIR}/scripts/01_system/02_set_time_and_timezone.sh"

echo "[3/11] Alle logging-retentie op maximaal 2 dagen zetten..."
bash "${SCRIPT_DIR}/scripts/01_system/03_configure_log_retention.sh"

echo "[4/11] SSH pakketten installeren..."
bash "${SCRIPT_DIR}/scripts/02_ssh/03_install_ssh_packages.sh"

echo "[5/11] Gebruiker '${MICHAEL_USER}' configureren..."
bash "${SCRIPT_DIR}/scripts/02_ssh/04_configure_michael_user.sh"

echo "[6/11] Root login uitschakelen en SSH hardenen..."
bash "${SCRIPT_DIR}/scripts/02_ssh/05_harden_ssh.sh"

echo "[7/11] Firewall pakketten installeren..."
bash "${SCRIPT_DIR}/scripts/03_firewall/06_install_firewall_packages.sh"

echo "[8/11] Firewall regels instellen..."
bash "${SCRIPT_DIR}/scripts/03_firewall/07_configure_firewall.sh"

echo "[9/11] WireGuard installeren en configureren..."
bash "${SCRIPT_DIR}/scripts/04_wireguard/08_install_wireguard.sh"

echo "[10/11] Controleren of alles goed is ingesteld (en zo nodig herstellen)..."
bash "${SCRIPT_DIR}/scripts/04_system/10_verify_and_repair.sh"

echo "[11/11] Opschonen van ongebruikte pakketten..."
bash "${SCRIPT_DIR}/scripts/04_system/11_cleanup.sh"

echo "Klaar. SSH draait op poort ${SSH_PORT}. Tijdzone staat op Europe/Amsterdam."
echo "Installatie succesvol afgerond. Systeem wordt nu automatisch herstart..."
reboot
