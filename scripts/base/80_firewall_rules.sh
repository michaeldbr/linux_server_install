#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/base/common.sh
source "${SCRIPT_DIR}/common.sh"

echo "[FIREWALL] Firewall configureren..."

# Zorg dat eigen chains bestaan en schoon zijn, zonder complete globale flush.
for chain in INPUT_BASE INPUT_SSH INPUT_WG INPUT_ROLE LOG_ACCEPT LOG_DROP; do
  iptables -N "${chain}" 2>/dev/null || true
  iptables -F "${chain}"
done

# Default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Logging chains
iptables -A LOG_ACCEPT -m limit --limit 10/min --limit-burst 20 -j LOG --log-prefix "IPTABLES ACCEPT: " --log-level 4
iptables -A LOG_ACCEPT -j ACCEPT

iptables -A LOG_DROP -m limit --limit 10/min --limit-burst 20 -j LOG --log-prefix "IPTABLES DROP: " --log-level 4
iptables -A LOG_DROP -j DROP

# INPUT hoofdrouting naar INPUT_BASE exact één keer.
while iptables -C INPUT -j INPUT_BASE >/dev/null 2>&1; do
  iptables -D INPUT -j INPUT_BASE
done
iptables -A INPUT -j INPUT_BASE

# BASE-regels
iptables -A INPUT_BASE -i lo -j ACCEPT
iptables -A INPUT_BASE -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# SSH en WireGuard doorsturen naar eigen chains
iptables -A INPUT_BASE -p tcp --dport "${SSH_PORT}" -j INPUT_SSH
iptables -A INPUT_BASE -p udp --dport "${WIREGUARD_PORT}" -j INPUT_WG

# Optioneel: ping toestaan
iptables -A INPUT_BASE -p icmp --icmp-type echo-request -j ACCEPT

# Rol-specifieke firewallregels via INPUT_ROLE chain
iptables -A INPUT_BASE -j INPUT_ROLE

# Alles wat overblijft loggen en droppen
iptables -A INPUT_BASE -j LOG_DROP

# SSH whitelist via ALLOWED_SSH_IPS CSV.
declare -a allowed_ssh_ips=()
parse_csv_to_array "${ALLOWED_SSH_IPS}" allowed_ssh_ips

if (( ${#allowed_ssh_ips[@]} == 0 )); then
  echo "[FIREWALL] FOUT: ALLOWED_SSH_IPS bevat geen geldige IP-adressen." >&2
  exit 1
fi

for ip in "${allowed_ssh_ips[@]}"; do
  iptables -A INPUT_SSH -s "${ip}" -j LOG_ACCEPT
done
iptables -A INPUT_SSH -j LOG_DROP

# WireGuard poort openzetten
iptables -A INPUT_WG -j ACCEPT

# INPUT_ROLE is bewust leeg in de base en wordt per rol gevuld.
iptables -A INPUT_ROLE -j RETURN

# Persist opslaan
iptables-save > /etc/iptables/rules.v4

case "${IPV6_POLICY}" in
  drop)
    ip6tables -F
    ip6tables -X
    ip6tables -P INPUT DROP
    ip6tables -P FORWARD DROP
    ip6tables -P OUTPUT DROP
    ip6tables-save > /etc/iptables/rules.v6
    ;;
  keep)
    echo "[FIREWALL] IPV6_POLICY=keep, bestaande IPv6 policy blijft ongewijzigd."
    ;;
  *)
    echo "[FIREWALL] FOUT: onbekende IPV6_POLICY='${IPV6_POLICY}', gebruik 'drop' of 'keep'." >&2
    exit 1
    ;;
esac

systemctl enable netfilter-persistent
netfilter-persistent save
netfilter-persistent reload

echo "[FIREWALL] Firewall succesvol ingesteld."
