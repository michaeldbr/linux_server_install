#!/usr/bin/env bash
set -euo pipefail

WG_DIR="/etc/wireguard"
WG_CONF="${WG_DIR}/wg0.conf"
WG_PRIVATE_KEY_FILE="${WG_DIR}/server_private.key"
WG_PUBLIC_KEY_FILE="${WG_DIR}/server_public.key"
WG_ADDRESS="${INTERNAL_IP}/24"
WG_PORT="51820"
DEFAULT_IFACE="$(ip route | awk '/default/ {print $5; exit}')"

if [[ -z "${INTERNAL_IP:-}" ]]; then
  echo "INTERNAL_IP ontbreekt. Start dit script via install.sh." >&2
  exit 1
fi

install_wireguard() {
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y wireguard wireguard-tools
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y wireguard-tools
  elif command -v yum >/dev/null 2>&1; then
    yum install -y wireguard-tools
  else
    echo "Geen ondersteunde package manager gevonden om WireGuard te installeren." >&2
    exit 1
  fi
}

prepare_keys() {
  mkdir -p "$WG_DIR"
  chmod 700 "$WG_DIR"

  if [[ ! -f "$WG_PRIVATE_KEY_FILE" ]]; then
    wg genkey > "$WG_PRIVATE_KEY_FILE"
    chmod 600 "$WG_PRIVATE_KEY_FILE"
  fi

  if [[ ! -f "$WG_PUBLIC_KEY_FILE" ]]; then
    wg pubkey < "$WG_PRIVATE_KEY_FILE" > "$WG_PUBLIC_KEY_FILE"
    chmod 644 "$WG_PUBLIC_KEY_FILE"
  fi
}

write_config_if_missing() {
  local private_key
  private_key="$(cat "$WG_PRIVATE_KEY_FILE")"

  if [[ ! -f "$WG_CONF" ]]; then
    cat > "$WG_CONF" <<CFG
[Interface]
Address = ${WG_ADDRESS}
ListenPort = ${WG_PORT}
PrivateKey = ${private_key}
SaveConfig = true
CFG
    chmod 600 "$WG_CONF"
  fi
}

enable_ip_forwarding() {
  cat > /etc/sysctl.d/99-wireguard-forward.conf <<'SYSCTL'
net.ipv4.ip_forward = 1
SYSCTL
  sysctl --system >/dev/null
}

start_wireguard() {
  systemctl enable --now wg-quick@wg0
}

install_wireguard
prepare_keys
write_config_if_missing
enable_ip_forwarding
start_wireguard

echo "WireGuard installatie gereed."
echo "Publieke server key: $(cat "$WG_PUBLIC_KEY_FILE")"
echo "Configuratie: $WG_CONF"
