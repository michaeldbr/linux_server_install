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

SERVER_IP="${WIREGUARD_SERVER_IP:?ERROR: WIREGUARD_SERVER_IP not set}"
if [[ ! "${SERVER_IP}" =~ ^10\.0\.0\.[0-9]{1,3}$ ]]; then
  echo "[WG] FOUT: Ongeldig WIREGUARD_SERVER_IP '${SERVER_IP}'." >&2
  echo "[WG] Gebruik formaat 10.0.0.X waarbij X tussen 1 en 254 ligt." >&2
  exit 1
fi

LAST_OCTET="${SERVER_IP##*.}"
if (( LAST_OCTET < 1 || LAST_OCTET > 254 )); then
  echo "[WG] FOUT: Ongeldig WIREGUARD_SERVER_IP '${SERVER_IP}'." >&2
  echo "[WG] Gebruik formaat 10.0.0.X waarbij X tussen 1 en 254 ligt." >&2
  exit 1
fi

SERVER_IP_CIDR="${SERVER_IP}/24"
echo "[WG] Intern server IP ingesteld op ${SERVER_IP_CIDR}"

echo "[WG] WireGuard directory voorbereiden..."
install -d -m 700 /etc/wireguard

if [[ ! -f "${PRIVATE_KEY_PATH}" ]]; then
  if [[ "${GENERATE_KEYS}" != "true" ]]; then
    echo "[WG] Let op: key generatie stond uit, maar private key ontbreekt. Er wordt alsnog een key pair gemaakt."
  fi
  echo "[WG] private key ontbreekt, genereren..."
  umask 077
  wg genkey > "${PRIVATE_KEY_PATH}"
fi

if [[ ! -f "${PUBLIC_KEY_PATH}" ]]; then
  echo "[WG] public key ontbreekt, genereren op basis van private key..."
  wg pubkey < "${PRIVATE_KEY_PATH}" > "${PUBLIC_KEY_PATH}"
fi

chmod 600 "${PRIVATE_KEY_PATH}"
chmod 644 "${PUBLIC_KEY_PATH}"

WG_CONF_PATH="/etc/wireguard/${INTERFACE}.conf"

echo "[WG] ${INTERFACE}.conf opbouwen..."
{
  echo "[Interface]"
  echo "PrivateKey = $(cat "${PRIVATE_KEY_PATH}")"
  echo "Address = ${SERVER_IP_CIDR}"
  echo "ListenPort = ${LISTEN_PORT}"
} > "${WG_CONF_PATH}"

chmod 600 "${WG_CONF_PATH}"

if [[ "${FORWARDING}" == "true" ]]; then
  echo "[WG] IP forwarding inschakelen..."
  sysctl -w net.ipv4.ip_forward=1 >/dev/null

  mkdir -p /etc/sysctl.d
  cat > /etc/sysctl.d/99-wireguard-forwarding.conf <<EOF
net.ipv4.ip_forward=1
EOF

  sysctl --system >/dev/null
fi

if [[ "${AUTO_START}" == "true" ]]; then
  echo "[WG] WireGuard service activeren..."
  systemctl enable "wg-quick@${INTERFACE}"
  systemctl restart "wg-quick@${INTERFACE}"
fi

echo "[WG] Validatie..."
if ! ip a show "${INTERFACE}" >/dev/null 2>&1; then
  echo "[WG] FOUT: ${INTERFACE} interface niet actief" >&2
  exit 1
fi

wg || true

echo "[WG] WireGuard succesvol actief op ${SERVER_IP_CIDR}"
