#!/usr/bin/env bash
set -euo pipefail

echo "[WG] WireGuard pakketten installeren..."
apt-get -y install wireguard wireguard-tools

if ! command -v wg >/dev/null 2>&1; then
  echo "[WG] FOUT: 'wg' command niet gevonden na installatie." >&2
  exit 1
fi

if [[ ! -f /etc/wireguard/wg0.conf ]]; then
  echo "[WG] WAARSCHUWING: /etc/wireguard/wg0.conf ontbreekt. WireGuard is nog niet geconfigureerd."
fi
