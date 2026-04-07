#!/usr/bin/env bash
set -euo pipefail

echo "[FIREWALL:worker] Rol-specifieke firewallregels toepassen..."

iptables -F INPUT_ROLE
iptables -A INPUT_ROLE -p tcp --dport 10250 -j LOG_ACCEPT
iptables -A INPUT_ROLE -j RETURN

iptables-save > /etc/iptables/rules.v4
netfilter-persistent save
netfilter-persistent reload

echo "[FIREWALL:worker] Klaar."
