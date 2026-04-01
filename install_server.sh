#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/00_common/common.sh
source "${SCRIPT_DIR}/scripts/00_common/common.sh"

if [[ ${EUID} -ne 0 ]]; then
  echo "Dit script moet als root worden uitgevoerd (bijv. met sudo)." >&2
  exit 1
fi

reboot_required=0

echo "[INIT] Shell scripts uitvoerbaar maken..."
find "${SCRIPT_DIR}/scripts" -type f -name '*.sh' -exec chmod +x {} +

echo "[1/10] Systeem pakketlijsten verversen en updates installeren..."
bash "${SCRIPT_DIR}/scripts/01_system/01_system_update.sh"

echo "[2/10] Tijd en datum synchroniseren + timezone Europe/Amsterdam instellen..."
bash "${SCRIPT_DIR}/scripts/01_system/02_set_time_and_timezone.sh"

echo "[3/10] SSH pakketten installeren..."
bash "${SCRIPT_DIR}/scripts/02_ssh/03_install_ssh_packages.sh"

echo "[4/10] Gebruiker '${MICHAEL_USER}' configureren..."
bash "${SCRIPT_DIR}/scripts/02_ssh/04_configure_michael_user.sh"

echo "[5/10] Root login uitschakelen en SSH hardenen..."
bash "${SCRIPT_DIR}/scripts/02_ssh/05_harden_ssh.sh"

echo "[6/10] Firewall pakketten installeren..."
bash "${SCRIPT_DIR}/scripts/03_firewall/06_install_firewall_packages.sh"

echo "[7/10] Firewall regels met chain 'ip' instellen..."
bash "${SCRIPT_DIR}/scripts/03_firewall/07_configure_firewall.sh"

echo "[8/10] WireGuard installeren..."
bash "${SCRIPT_DIR}/scripts/03_firewall/09_install_wireguard.sh"

echo "[9/10] Controleren of alles goed is ingesteld (en zo nodig herstellen)..."
bash "${SCRIPT_DIR}/scripts/04_system/10_verify_and_repair.sh"

echo "[10/10] Opschonen van ongebruikte pakketten..."
bash "${SCRIPT_DIR}/scripts/04_system/11_cleanup.sh"

echo "Klaar. SSH draait op poort ${SSH_PORT}. WireGuard luistert op UDP poort ${WIREGUARD_PORT}. Tijdzone staat op Europe/Amsterdam."

running_kernel="$(uname -r)"
boot_target_kernel="$(basename "$(readlink -f /boot/vmlinuz 2>/dev/null || true)" | sed 's/^vmlinuz-//')"
if [[ -n "${boot_target_kernel}" && "${running_kernel}" != "${boot_target_kernel}" ]]; then
  echo "WAARSCHUWING: Nieuwe kernel gedetecteerd maar nog niet actief."
  echo " - Running kernel : ${running_kernel}"
  echo " - Nieuwe kernel  : ${boot_target_kernel}"
  reboot_required=1
fi

if [[ -f /var/run/reboot-required ]]; then
  echo "WAARSCHUWING: Reboot vereist om alle updates volledig toe te passen."
  reboot_required=1
fi

if [[ "${reboot_required}" -eq 1 ]]; then
  echo "Systeem wordt nu éénmalig herstart (na afronding van alle stappen)..."
  reboot
fi
