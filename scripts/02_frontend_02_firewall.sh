#!/usr/bin/env bash
set -euo pipefail

iptables -C INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -C INPUT -p tcp --dport 443 -j ACCEPT >/dev/null 2>&1 || iptables -A INPUT -p tcp --dport 443 -j ACCEPT

ip6tables -C INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || ip6tables -A INPUT -p tcp --dport 80 -j ACCEPT
ip6tables -C INPUT -p tcp --dport 443 -j ACCEPT >/dev/null 2>&1 || ip6tables -A INPUT -p tcp --dport 443 -j ACCEPT

if command -v iptables-save >/dev/null 2>&1; then
  mkdir -p /etc/iptables
  iptables-save > /etc/iptables/rules.v4
fi

if command -v ip6tables-save >/dev/null 2>&1; then
  mkdir -p /etc/iptables
  ip6tables-save > /etc/iptables/rules.v6
fi

echo "Frontend firewall regels toegepast (80/443)."
