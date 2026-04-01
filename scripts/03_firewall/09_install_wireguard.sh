#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/00_common/common.sh
source "${SCRIPT_DIR}/../00_common/common.sh"

echo "[WG] WireGuard pakketten installeren..."
apt-get -y install wireguard wireguard-tools

if ! command -v wg >/dev/null 2>&1; then
  echo "[WG] FOUT: 'wg' command niet gevonden na installatie." >&2
  exit 1
fi

install -d -m 700 /etc/wireguard

if [[ ! -f /etc/wireguard/privatekey ]]; then
  echo "[WG] privatekey ontbreekt, genereren..."
  wg genkey > /etc/wireguard/privatekey
fi
chmod 600 /etc/wireguard/privatekey

wg pubkey < /etc/wireguard/privatekey > /etc/wireguard/publickey
chmod 644 /etc/wireguard/publickey

if [[ ! -f /etc/wireguard/wg0.conf ]]; then
  if [[ -z "${WG_IP:-}" ]]; then
    echo "[WG] FOUT: WG_IP environment variable is verplicht om wg0.conf te genereren." >&2
    exit 1
  fi
  echo "[WG] wg0.conf ontbreekt, minimale configuratie aanmaken..."
  {
    echo "[Interface]"
    echo "PrivateKey = $(cat /etc/wireguard/privatekey)"
    echo "Address = ${WG_IP}"
    echo "ListenPort = ${WIREGUARD_PORT}"
    echo "SaveConfig = true"
  } > /etc/wireguard/wg0.conf
fi
chmod 600 /etc/wireguard/wg0.conf

echo "[WG] IP forwarding inschakelen..."
sysctl -w net.ipv4.ip_forward=1
if grep -qE '^\s*net\.ipv4\.ip_forward\s*=' /etc/sysctl.conf; then
  sed -i 's/^\s*net\.ipv4\.ip_forward\s*=.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
else
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi

echo "[WG] Firewall regels voor WireGuard/forwarding toepassen..."
while iptables -C INPUT -p udp --dport "${WIREGUARD_PORT}" -j ACCEPT 2>/dev/null; do
  iptables -D INPUT -p udp --dport "${WIREGUARD_PORT}" -j ACCEPT
done
iptables -A INPUT -p udp --dport "${WIREGUARD_PORT}" -j ACCEPT
iptables -P FORWARD ACCEPT
iptables-save > /etc/iptables/rules.v4

echo "[WG] WireGuard service activeren..."
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

echo "[WG] Validatie..."
wg
ip a show wg0 >/dev/null
echo "[WG] WireGuard is actief en klaar voor multi-node peers."
