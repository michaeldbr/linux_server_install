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
iptables -X LOG_ACCEPT 2>/dev/null || true
iptables -X LOG_DROP 2>/dev/null || true

# ========================
# DEFAULT POLICIES
# ========================
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# ========================
# CUSTOM LOG CHAINS
# ========================
iptables -N LOG_ACCEPT
iptables -N LOG_DROP

# ========================
# LOG ACCEPT (per type)
# ========================

# SSH logging
iptables -A LOG_ACCEPT -p tcp --dport 40111 -m limit --limit 10/min --limit-burst 20 -j LOG --log-prefix "ACCEPT_SSH: " --log-level 4
iptables -A LOG_ACCEPT -p tcp --dport 40111 -j ACCEPT

# WireGuard logging
iptables -A LOG_ACCEPT -p udp --dport 51820 -m limit --limit 10/min --limit-burst 20 -j LOG --log-prefix "ACCEPT_WG: " --log-level 4
iptables -A LOG_ACCEPT -p udp --dport 51820 -j ACCEPT

# Internal WG subnet logging
iptables -A LOG_ACCEPT -s 10.0.0.0/24 -m limit --limit 20/min --limit-burst 50 -j LOG --log-prefix "ACCEPT_INTERNAL: " --log-level 4
iptables -A LOG_ACCEPT -s 10.0.0.0/24 -j ACCEPT

# Established verkeer (belangrijk, maar minder spam)
iptables -A LOG_ACCEPT -m conntrack --ctstate RELATED,ESTABLISHED -m limit --limit 30/min --limit-burst 50 -j LOG --log-prefix "ACCEPT_ESTABLISHED: " --log-level 4
iptables -A LOG_ACCEPT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Loopback (bijna nooit loggen nodig, maar voor compleetheid)
iptables -A LOG_ACCEPT -i lo -m limit --limit 5/min --limit-burst 10 -j LOG --log-prefix "ACCEPT_LOOPBACK: " --log-level 4
iptables -A LOG_ACCEPT -i lo -j ACCEPT

# ========================
# LOG DROP
# ========================
iptables -A LOG_DROP -m limit --limit 20/min --limit-burst 50 -j LOG --log-prefix "DROP_INPUT: " --log-level 4
iptables -A LOG_DROP -j DROP

# ========================
# INPUT RULES
# ========================
iptables -A INPUT -i lo -j LOG_ACCEPT
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --dport 40111 -j LOG_ACCEPT
iptables -A INPUT -p udp --dport 51820 -j LOG_ACCEPT
iptables -A INPUT -s 10.0.0.0/24 -j LOG_ACCEPT

# alles wat overblijft
iptables -A INPUT -j LOG_DROP

# Kubernetes / interne forwarding toestaan
iptables -A FORWARD -s 10.0.0.0/24 -j ACCEPT
iptables -A FORWARD -d 10.0.0.0/24 -j ACCEPT

# IPv6 firewall toepassen (established accept, daarna drop)
ip6tables -F
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT ACCEPT
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
ip6tables -A INPUT -p tcp --dport 40111 -j ACCEPT
ip6tables -A INPUT -p udp --dport 51820 -j ACCEPT
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

echo "Firewall regels toegepast voor IPv4 en IPv6."
