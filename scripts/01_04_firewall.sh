#!/usr/bin/env bash
set -euo pipefail

if ! command -v iptables >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y iptables
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y iptables iptables-services
  elif command -v yum >/dev/null 2>&1; then
    yum install -y iptables iptables-services
  else
    echo "iptables niet gevonden en geen ondersteunde package manager beschikbaar." >&2
    exit 1
  fi
fi

if ! command -v ip6tables >/dev/null 2>&1; then
  echo "ip6tables ontbreekt; IPv6 firewall regels kunnen niet toegepast worden." >&2
  exit 1
fi

# Reset bestaande regels voor idempotent gedrag
iptables -F
iptables -X LOG_DROP 2>/dev/null || true

# Default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Drop-chain met logging
iptables -N LOG_DROP
iptables -A LOG_DROP -m limit --limit 20/min --limit-burst 50 -j LOG --log-prefix "DROP_INPUT: " --log-level 4
iptables -A LOG_DROP -j DROP

# INPUT regels voor huidige setup (SSH + WireGuard)
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --dport 40111 -j ACCEPT
iptables -A INPUT -p tcp --dport 40112 -j ACCEPT
iptables -A INPUT -p udp --dport 51820 -j ACCEPT
iptables -A INPUT -p icmp -j ACCEPT
iptables -A INPUT -j LOG_DROP

# FORWARD voor WireGuard subnet
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -s 10.0.0.0/24 -j ACCEPT
iptables -A FORWARD -d 10.0.0.0/24 -j ACCEPT

# IPv6 firewall toepassen (zelfde basis)
ip6tables -F
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT ACCEPT
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
ip6tables -A INPUT -p tcp --dport 40111 -j ACCEPT
ip6tables -A INPUT -p tcp --dport 40112 -j ACCEPT
ip6tables -A INPUT -p udp --dport 51820 -j ACCEPT
ip6tables -A INPUT -p ipv6-icmp -j ACCEPT
ip6tables -A INPUT -j DROP
ip6tables -A FORWARD -j DROP

if command -v iptables-save >/dev/null 2>&1; then
  mkdir -p /etc/iptables
  iptables-save > /etc/iptables/rules.v4
fi

if command -v ip6tables-save >/dev/null 2>&1; then
  mkdir -p /etc/iptables
  ip6tables-save > /etc/iptables/rules.v6
fi

echo "Firewall regels toegepast voor huidige setup (SSH + WireGuard)."
