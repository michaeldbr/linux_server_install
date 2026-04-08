#!/usr/bin/env bash
set -euo pipefail

echo "[FIREWALL:master] Rol-specifieke firewallregels toepassen..."

iptables -F INPUT_ROLE
iptables -A INPUT_ROLE -p tcp --dport 6443 -j LOG_ACCEPT
iptables -A INPUT_ROLE -p tcp --dport 2379:2380 -j LOG_ACCEPT
iptables -A INPUT_ROLE -p tcp --dport 10250 -j LOG_ACCEPT
iptables -A INPUT_ROLE -p tcp --dport 10257 -j LOG_ACCEPT
iptables -A INPUT_ROLE -p tcp --dport 10259 -j LOG_ACCEPT
iptables -A INPUT_ROLE -p 112 -j LOG_ACCEPT
iptables -A INPUT_ROLE -j RETURN

iptables-save > /etc/iptables/rules.v4
netfilter-persistent save
netfilter-persistent reload

echo "[FIREWALL:master] Klaar."
