#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
CONFIG_FILE="${REPO_ROOT}/wireguard/config.json"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "[WG] FOUT: Config niet gevonden op ${CONFIG_FILE}" >&2
  exit 1
fi

echo "[WG] WireGuard pakketten installeren..."
apt-get -y install wireguard wireguard-tools

if ! command -v wg >/dev/null 2>&1; then
  echo "[WG] FOUT: 'wg' command niet gevonden na installatie." >&2
  exit 1
fi

readarray -t WG_CONFIG < <(python3 - "${CONFIG_FILE}" <<'PY'
import json
import sys

cfg_path = sys.argv[1]
with open(cfg_path, "r", encoding="utf-8") as f:
    cfg = json.load(f)

wg = cfg.get("wireguard", {})
if not wg.get("enabled", False):
    print("ENABLED=false")
    sys.exit(0)

print("ENABLED=true")
print(f"INTERFACE={wg.get('interface', 'wg0')}")
print(f"SERVER_IP={wg.get('network', {}).get('server_ip', '10.0.0.1/24')}")
print(f"LISTEN_PORT={wg.get('network', {}).get('listen_port', 51820)}")
print(f"PRIVATE_KEY_PATH={wg.get('keys', {}).get('private_key_path', '/etc/wireguard/private.key')}")
print(f"PUBLIC_KEY_PATH={wg.get('keys', {}).get('public_key_path', '/etc/wireguard/public.key')}")
print(f"GENERATE_KEYS={str(wg.get('keys', {}).get('generate', True)).lower()}")
print(f"FORWARDING={str(wg.get('firewall', {}).get('forwarding', True)).lower()}")
print(f"AUTO_START={str(wg.get('auto_start', True)).lower()}")
PY
)

for item in "${WG_CONFIG[@]}"; do
  eval "${item}"
done

if [[ "${ENABLED}" != "true" ]]; then
  echo "[WG] WireGuard staat disabled in config.json, stap wordt overgeslagen."
  exit 0
fi

if [[ ! -r /dev/tty ]]; then
  echo "[WG] FOUT: Geen interactieve terminal beschikbaar voor IP-invoer." >&2
  echo "[WG] Start dit script in een interactieve SSH-sessie (met TTY)." >&2
  exit 1
fi

while true; do
  read -r -p "Wat is het interne IP adres van deze server? (10.0.0...): " INPUT_SERVER_IP < /dev/tty
  read -r -p "Voer het interne IP adres nogmaals in ter verificatie: " VERIFY_SERVER_IP < /dev/tty

  if [[ -z "${INPUT_SERVER_IP}" || -z "${VERIFY_SERVER_IP}" ]]; then
    echo "[WG] Lege invoer is niet toegestaan. Probeer het opnieuw."
    continue
  fi

  if [[ "${INPUT_SERVER_IP}" != "${VERIFY_SERVER_IP}" ]]; then
    echo "[WG] Invoer komt niet overeen. Probeer het opnieuw."
    continue
  fi

  if [[ "${INPUT_SERVER_IP}" =~ ^10\.0\.0\.[0-9]{1,3}$ ]]; then
    LAST_OCTET="${INPUT_SERVER_IP##*.}"
    if (( LAST_OCTET >= 1 && LAST_OCTET <= 254 )); then
      SERVER_IP="${INPUT_SERVER_IP}/24"
      echo "[WG] Intern server IP ingesteld op ${SERVER_IP}"
      break
    fi
  fi

  echo "[WG] Ongeldig IP. Gebruik een adres zoals 10.0.0.2"
done

echo "[WG] WireGuard directory voorbereiden..."
install -d -m 700 /etc/wireguard

if [[ "${GENERATE_KEYS}" == "true" && ! -f "${PRIVATE_KEY_PATH}" ]]; then
  echo "[WG] private key ontbreekt, genereren..."
  umask 077
  wg genkey > "${PRIVATE_KEY_PATH}"
fi

if [[ ! -f "${PUBLIC_KEY_PATH}" ]]; then
  echo "[WG] public key genereren..."
  wg pubkey < "${PRIVATE_KEY_PATH}" > "${PUBLIC_KEY_PATH}"
fi

chmod 600 "${PRIVATE_KEY_PATH}"
chmod 644 "${PUBLIC_KEY_PATH}"

WG_CONF_PATH="/etc/wireguard/${INTERFACE}.conf"

echo "[WG] ${INTERFACE}.conf opbouwen..."
{
  echo "[Interface]"
  echo "PrivateKey = $(cat "${PRIVATE_KEY_PATH}")"
  echo "Address = ${SERVER_IP}"
  echo "ListenPort = ${LISTEN_PORT}"
  echo "SaveConfig = true"
} > "${WG_CONF_PATH}"

chmod 600 "${WG_CONF_PATH}"

if [[ "${FORWARDING}" == "true" ]]; then
  echo "[WG] IP forwarding inschakelen..."
  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi

echo "[WG] Firewallregel voor UDP ${LISTEN_PORT} toevoegen..."
iptables -N wireguard 2>/dev/null || true
iptables -F wireguard
iptables -A wireguard -j DROP
while iptables -C INPUT -p udp --dport "${LISTEN_PORT}" -j wireguard 2>/dev/null; do
  iptables -D INPUT -p udp --dport "${LISTEN_PORT}" -j wireguard
done
while iptables -C INPUT -p udp --dport "${LISTEN_PORT}" -j ACCEPT 2>/dev/null; do
  iptables -D INPUT -p udp --dport "${LISTEN_PORT}" -j ACCEPT
done
iptables -A INPUT -p udp --dport "${LISTEN_PORT}" -j wireguard
iptables-save > /etc/iptables/rules.v4

if [[ "${AUTO_START}" == "true" ]]; then
  echo "[WG] WireGuard service activeren..."
  systemctl enable "wg-quick@${INTERFACE}"
  systemctl restart "wg-quick@${INTERFACE}"
fi

echo "[WG] Validatie..."
wg || true

if ip a show "${INTERFACE}" >/dev/null 2>&1; then
  echo "[WG] Interface ${INTERFACE} actief"
else
  echo "[WG] FOUT: ${INTERFACE} interface niet actief" >&2
  exit 1
fi

echo "[WG] WireGuard succesvol actief op ${SERVER_IP}"
