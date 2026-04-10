#!/usr/bin/env bash
set -euo pipefail

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

install_wireguard

echo "WireGuard installatie gereed."
