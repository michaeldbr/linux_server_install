#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/00_common/common.sh
source "${SCRIPT_DIR}/../00_common/common.sh"

echo "[FIREWALL] Firewall configureren..."

# Reset bestaande IPv4 regels
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# Default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Nieuwe chains
iptables -N INPUT_BASE
iptables -N INPUT_SSH
iptables -N INPUT_WG
iptables -N LOG_ACCEPT
iptables -N LOG_DROP

# Logging chains
iptables -A LOG_ACCEPT -m limit --limit 10/min --limit-burst 20 -j LOG --log-prefix "IPTABLES ACCEPT: " --log-level 4
iptables -A LOG_ACCEPT -j ACCEPT

iptables -A LOG_DROP -m limit --limit 10/min --limit-burst 20 -j LOG --log-prefix "IPTABLES DROP: " --log-level 4
iptables -A LOG_DROP -j DROP

# INPUT hoofdrouting
iptables -A INPUT -j INPUT_BASE

# BASE-regels
iptables -A INPUT_BASE -i lo -j ACCEPT
iptables -A INPUT_BASE -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# SSH en WireGuard doorsturen naar eigen chains
iptables -A INPUT_BASE -p tcp --dport "${SSH_PORT}" -j INPUT_SSH
iptables -A INPUT_BASE -p udp --dport "${WIREGUARD_PORT}" -j INPUT_WG

# Optioneel: ping toestaan
iptables -A INPUT_BASE -p icmp --icmp-type echo-request -j ACCEPT

# Alles wat overblijft loggen en droppen
iptables -A INPUT_BASE -j LOG_DROP

# SSH whitelist
iptables -A INPUT_SSH -s "${ALLOWED_IP_1}" -j LOG_ACCEPT
iptables -A INPUT_SSH -s "${ALLOWED_IP_2}" -j LOG_ACCEPT
iptables -A INPUT_SSH -j LOG_DROP

# WireGuard poort openzetten
# Let op: hier niet op source-IP filteren, omdat peers/providers kunnen wisselen.
iptables -A INPUT_WG -j ACCEPT

# Persist opslaan
iptables-save > /etc/iptables/rules.v4

# IPv6 volledig blokkeren
ip6tables -F
ip6tables -X
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT DROP
ip6tables-save > /etc/iptables/rules.v6

systemctl enable netfilter-persistent
netfilter-persistent save
netfilter-persistent reload

echo "[FIREWALL] Firewall succesvol ingesteld."
