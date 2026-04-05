#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/00_common/common.sh
source "${SCRIPT_DIR}/../00_common/common.sh"

############################
# VARIABELEN
############################
SSH_PORT="${SSH_PORT:-40111}"

############################
# IPV6 UITZETTEN (HARD BLOCK)
############################
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT DROP

############################
# RESET FIREWALL
############################
iptables -F
iptables -X
iptables -t nat -F

############################
# DEFAULT POLICIES
############################
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

############################
# CHAINS
############################
iptables -N INPUT_BASE
iptables -N INPUT_SSH
iptables -N INPUT_SSH_CHECK
iptables -N INPUT_WG
iptables -N INPUT_WG_CHECK

iptables -N LOG_ACCEPT_BASE
iptables -N LOG_ACCEPT_SSH
iptables -N LOG_ACCEPT_WG
iptables -N LOG_DROP_INVALID
iptables -N LOG_DROP_SSH
iptables -N LOG_DROP_DEFAULT

############################
# LOGGING CHAINS
############################

iptables -A LOG_ACCEPT_BASE -m limit --limit 5/second -j LOG --log-prefix "ACCEPT_BASE SRC=" --log-level 4
iptables -A LOG_ACCEPT_BASE -j ACCEPT

iptables -A LOG_ACCEPT_SSH -m limit --limit 5/second -j LOG --log-prefix "ACCEPT_SSH SRC=" --log-level 4
iptables -A LOG_ACCEPT_SSH -j ACCEPT

iptables -A LOG_ACCEPT_WG -m limit --limit 5/second -j LOG --log-prefix "ACCEPT_WG SRC=" --log-level 4
iptables -A LOG_ACCEPT_WG -j ACCEPT

iptables -A LOG_DROP_INVALID -m limit --limit 5/second -j LOG --log-prefix "DROP_INVALID SRC=" --log-level 4
iptables -A LOG_DROP_INVALID -j DROP

iptables -A LOG_DROP_SSH -m limit --limit 5/second -j LOG --log-prefix "DROP_SSH SRC=" --log-level 4
iptables -A LOG_DROP_SSH -j DROP

iptables -A LOG_DROP_DEFAULT -m limit --limit 5/second -j LOG --log-prefix "DROP_UNKNOWN SRC=" --log-level 4
iptables -A LOG_DROP_DEFAULT -j DROP

############################
# BASE
############################

iptables -A INPUT_BASE -i lo -j LOG_ACCEPT_BASE
iptables -A INPUT_BASE -m conntrack --ctstate ESTABLISHED,RELATED -j LOG_ACCEPT_BASE

# INVALID packets
iptables -A INPUT -m conntrack --ctstate INVALID -j LOG_DROP_INVALID

############################
# TCP HARDENING (ANTI SCAN)
############################

iptables -A INPUT -p tcp ! --syn -m conntrack --ctstate NEW -j LOG_DROP_INVALID
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j LOG_DROP_INVALID
iptables -A INPUT -p tcp --tcp-flags ALL ALL -j LOG_DROP_INVALID

############################
# SSH
############################

iptables -A INPUT_SSH -p tcp --dport "$SSH_PORT" -j INPUT_SSH_CHECK

# rate limit
iptables -A INPUT_SSH_CHECK -p tcp --dport "$SSH_PORT" -m conntrack --ctstate NEW \
  -m hashlimit --hashlimit 3/min --hashlimit-burst 5 --hashlimit-mode srcip \
  --hashlimit-name ssh_limit -j LOG_ACCEPT_SSH

# brute force detectie
iptables -A INPUT_SSH_CHECK -m recent --set --name SSH
iptables -A INPUT_SSH_CHECK -m recent --update --seconds 60 --hitcount 10 --name SSH \
  -j LOG_DROP_SSH

iptables -A INPUT_SSH_CHECK -j LOG_DROP_SSH

############################
# WIREGUARD
############################

iptables -A INPUT_WG -p udp --dport 51820 -j INPUT_WG_CHECK
iptables -A INPUT_WG_CHECK -j LOG_ACCEPT_WG

############################
# INPUT FLOW
############################

iptables -A INPUT -j INPUT_BASE
iptables -A INPUT -p tcp --dport "$SSH_PORT" -j INPUT_SSH
iptables -A INPUT -p udp --dport 51820 -j INPUT_WG

# ICMP beperkt
iptables -A INPUT -p icmp -m limit --limit 1/second -j LOG_ACCEPT_BASE

# Default
iptables -A INPUT -j LOG_DROP_DEFAULT

############################
# OUTPUT (BELANGRIJK!)
############################

iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT

# alles loggen wat eruit wil maar niet mag
iptables -A OUTPUT -j LOG_DROP_DEFAULT

############################
# FORWARD (WIREGUARD / K8S)
############################

iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i wg0 -j ACCEPT
iptables -A FORWARD -o wg0 -j ACCEPT

iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

systemctl enable netfilter-persistent
netfilter-persistent save
netfilter-persistent reload
