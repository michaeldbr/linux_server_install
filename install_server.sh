#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/00_common/common.sh
source "${SCRIPT_DIR}/scripts/00_common/common.sh"

if [[ ${EUID} -ne 0 ]]; then
  echo "Dit script moet als root worden uitgevoerd (bijv. met sudo)." >&2
  exit 1
fi

validate_wireguard_ip() {
  local ip="${1:-}"

  if [[ ! "${ip}" =~ ^10\.0\.0\.[0-9]{1,3}$ ]]; then
    return 1
  fi

  local last_octet="${ip##*.}"
  (( last_octet >= 1 && last_octet <= 254 ))
}

echo "[PRE-FLIGHT] Benodigde invoer verzamelen..."
if [[ -z "${WIREGUARD_SERVER_IP:-}" ]]; then
  read -r -p "Voer het WireGuard server IP in (bijv. 10.0.0.2): " WIREGUARD_SERVER_IP
fi

if ! validate_wireguard_ip "${WIREGUARD_SERVER_IP}"; then
  echo "[PRE-FLIGHT] FOUT: Ongeldig WireGuard IP '${WIREGUARD_SERVER_IP}'." >&2
  echo "[PRE-FLIGHT] Gebruik formaat 10.0.0.X waarbij X tussen 1 en 254 ligt." >&2
  exit 1
fi

export WIREGUARD_SERVER_IP
echo "[PRE-FLIGHT] WireGuard server IP ingesteld op ${WIREGUARD_SERVER_IP}."

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

echo "[8/10] WireGuard installeren en configureren..."
bash "${SCRIPT_DIR}/scripts/04_wireguard/08_install_wireguard.sh"

echo "[9/10] Controleren of alles goed is ingesteld (en zo nodig herstellen)..."
bash "${SCRIPT_DIR}/scripts/04_system/10_verify_and_repair.sh"

echo "[10/10] Opschonen van ongebruikte pakketten..."
bash "${SCRIPT_DIR}/scripts/04_system/11_cleanup.sh"

echo "Klaar. SSH draait op poort ${SSH_PORT}. Tijdzone staat op Europe/Amsterdam."
echo "Installatie succesvol afgerond. Systeem wordt nu automatisch herstart..."
reboot
