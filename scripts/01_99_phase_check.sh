#!/usr/bin/env bash
set -euo pipefail

if ! systemctl is-active --quiet ssh && ! systemctl is-active --quiet sshd; then
  echo "SSH service is niet actief." >&2
  exit 1
fi

if ! systemctl is-active --quiet cron && ! systemctl is-active --quiet crond; then
  echo "Cron service is niet actief." >&2
  exit 1
fi

if ! iptables -S INPUT | grep -q -- '-P INPUT DROP'; then
  echo "Firewall INPUT policy staat niet op DROP." >&2
  exit 1
fi

if ! iptables -C INPUT -p tcp --dport 40111 -j ACCEPT >/dev/null 2>&1; then
  echo "Firewall SSH regel (40111) ontbreekt." >&2
  exit 1
fi

if ! iptables -C INPUT -p udp --dport 51820 -j ACCEPT >/dev/null 2>&1; then
  echo "Firewall WireGuard regel (51820) ontbreekt." >&2
  exit 1
fi

if ! systemctl is-active --quiet wg-quick@wg0; then
  echo "WireGuard service wg-quick@wg0 is niet actief." >&2
  exit 1
fi

if ! wg show wg0 >/dev/null 2>&1; then
  echo "WireGuard interface wg0 is niet actief." >&2
  exit 1
fi

echo "Fase 1 controle succesvol."
