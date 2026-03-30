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

for proto in tcp udp; do
  for port in "${SSH_PORT}" "${WEBMIN_PORT}"; do
    while iptables -C INPUT -p "${proto}" --dport "${port}" -j ip 2>/dev/null; do
      iptables -D INPUT -p "${proto}" --dport "${port}" -j ip
    done
    iptables -A INPUT -p "${proto}" --dport "${port}" -j ip
  done
done

iptables-save > /etc/iptables/rules.v4
systemctl enable netfilter-persistent
netfilter-persistent save
netfilter-persistent reload
