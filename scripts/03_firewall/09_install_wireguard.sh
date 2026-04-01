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

echo "[WG] WireGuard directory voorbereiden..."
install -d -m 700 /etc/wireguard

# 🔐 Veilige key generatie
if [[ ! -f /etc/wireguard/privatekey ]]; then
  echo "[WG] privatekey ontbreekt, genereren..."
  umask 077
  wg genkey > /etc/wireguard/privatekey
fi

if [[ ! -f /etc/wireguard/publickey ]]; then
  echo "[WG] publickey genereren..."
  wg pubkey < /etc/wireguard/privatekey > /etc/wireguard/publickey
fi

chmod 600 /etc/wireguard/privatekey
chmod 644 /etc/wireguard/publickey

echo "[WG] Keys klaar."

# ⚠️ Alleen configureren als WG_IP aanwezig is
if [[ -z "${WG_IP:-}" ]]; then
  echo "[WG] WG_IP niet gezet → WireGuard alleen geïnstalleerd (geen configuratie)"
  exit 0
fi

echo "[WG] WG_IP gedetecteerd (${WG_IP}) → configuratie starten..."

# Config alleen maken als hij nog niet bestaat
if [[ ! -f /etc/wireguard/wg0.conf ]]; then
  echo "[WG] wg0.conf aanmaken..."

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
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# persist maken
sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

echo "[WG] Firewall regels instellen..."

# INPUT rule (idempotent)
iptables -C INPUT -p udp --dport "${WIREGUARD_PORT}" -j ACCEPT 2>/dev/null || \
  iptables -A INPUT -p udp --dport "${WIREGUARD_PORT}" -j ACCEPT

# FORWARD policy
iptables -P FORWARD ACCEPT

# opslaan
iptables-save > /etc/iptables/rules.v4

echo "[WG] WireGuard service activeren..."
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

echo "[WG] Validatie..."

# Niet laten crashen bij check
wg || true

if ip a show wg0 >/dev/null 2>&1; then
  echo "[WG] Interface wg0 actief"
else
  echo "[WG] FOUT: wg0 interface niet actief" >&2
  exit 1
fi

echo "[WG] WireGuard succesvol actief op ${WG_IP}"
echo "[WG] Server klaar voor multi-node uitbreiding"
