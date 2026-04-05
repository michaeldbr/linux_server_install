#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/00_common/common.sh
source "${SCRIPT_DIR}/../00_common/common.sh"

iptables -N ip 2>/dev/null || true
iptables -F ip
iptables -A ip -s "${ALLOWED_IP_1}" -j ACCEPT
iptables -A ip -s "${ALLOWED_IP_2}" -j ACCEPT
iptables -A ip -j DROP

iptables -N wireguard 2>/dev/null || true
iptables -F wireguard
iptables -A wireguard -j DROP


# WireGuard: UDP poort openzetten (server endpoint)
while iptables -C INPUT -p udp --dport "${WIREGUARD_PORT}" -j wireguard 2>/dev/null; do
  iptables -D INPUT -p udp --dport "${WIREGUARD_PORT}" -j wireguard
done
while iptables -C INPUT -p udp --dport "${WIREGUARD_PORT}" -j ACCEPT 2>/dev/null; do
  iptables -D INPUT -p udp --dport "${WIREGUARD_PORT}" -j ACCEPT
done
iptables -A INPUT -p udp --dport "${WIREGUARD_PORT}" -j wireguard

while iptables -C INPUT -p tcp --dport "${SSH_PORT}" -j ip 2>/dev/null; do
  iptables -D INPUT -p tcp --dport "${SSH_PORT}" -j ip
done
iptables -A INPUT -p tcp --dport "${SSH_PORT}" -j ip

iptables-save > /etc/iptables/rules.v4

# Blokkeer al het IPv6-verkeer
ip6tables -F
ip6tables -X
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT DROP
ip6tables-save > /etc/iptables/rules.v6

systemctl enable netfilter-persistent
netfilter-persistent save
netfilter-persistent reload
