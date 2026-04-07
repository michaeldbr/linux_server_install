#!/usr/bin/env bash
set -euo pipefail

echo "[FIREWALL:traffic] Rol-specifieke firewallregels toepassen..."

iptables -F INPUT_ROLE
iptables -A INPUT_ROLE -p tcp --dport 80 -j LOG_ACCEPT
iptables -A INPUT_ROLE -p tcp --dport 443 -j LOG_ACCEPT
iptables -A INPUT_ROLE -j RETURN

iptables-save > /etc/iptables/rules.v4
netfilter-persistent save
netfilter-persistent reload

echo "[FIREWALL:traffic] Klaar."
