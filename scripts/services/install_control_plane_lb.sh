#!/usr/bin/env bash
set -euo pipefail

ROLE_NAME="${1:-}"
CONTROL_PLANE_ENDPOINT="${2:-}"
CONTROL_PLANE_BACKENDS="${CONTROL_PLANE_BACKENDS:-}"
HAPROXY_BIND_PORT="${HAPROXY_BIND_PORT:-7443}"

if [[ -z "${ROLE_NAME}" ]]; then
  echo "[SERVICES] FOUT: role argument ontbreekt." >&2
  exit 1
fi

if [[ -z "${CONTROL_PLANE_ENDPOINT}" ]]; then
  echo "[SERVICES] FOUT: control plane endpoint ontbreekt." >&2
  exit 1
fi

if ! command -v ip >/dev/null 2>&1; then
  echo "[SERVICES:${ROLE_NAME}] FOUT: 'ip' command ontbreekt, netwerkinterface kan niet bepaald worden." >&2
  exit 1
fi

KEEPALIVED_INTERFACE="${KEEPALIVED_INTERFACE:-}"

if [[ -z "${KEEPALIVED_INTERFACE}" ]] && ip link show wg0 >/dev/null 2>&1; then
  KEEPALIVED_INTERFACE="wg0"
fi

if [[ -z "${KEEPALIVED_INTERFACE}" ]]; then
  KEEPALIVED_INTERFACE="$(ip route get "${CONTROL_PLANE_ENDPOINT}" 2>/dev/null | awk '/dev/ {for (i=1; i<=NF; i++) if ($i == "dev") {print $(i+1); exit}}')"
fi

if [[ -z "${KEEPALIVED_INTERFACE}" || "${KEEPALIVED_INTERFACE}" == "lo" ]]; then
  KEEPALIVED_INTERFACE="$(ip route show default 2>/dev/null | awk '/default/ {for (i=1; i<=NF; i++) if ($i == "dev") {print $(i+1); exit}}')"
fi

if [[ -z "${KEEPALIVED_INTERFACE}" || "${KEEPALIVED_INTERFACE}" == "lo" ]]; then
  echo "[SERVICES:${ROLE_NAME}] FOUT: kon netwerkinterface voor keepalived niet bepalen (of detecteerde alleen lo)." >&2
  exit 1
fi

case "${ROLE_NAME}" in
  first-master)
    KEEPALIVED_STATE="MASTER"
    KEEPALIVED_PRIORITY="200"
    HAPROXY_BIND_ADDRESS="0.0.0.0:${HAPROXY_BIND_PORT}"
    KEEPALIVED_ROUTER_NAME="master1"
    KEEPALIVED_UNICAST_SRC_IP="${KEEPALIVED_UNICAST_SRC_IP:-${WIREGUARD_SERVER_IP:-10.0.0.1}}"
    KEEPALIVED_UNICAST_PEERS="${KEEPALIVED_UNICAST_PEERS:-10.0.0.2}"
    KEEPALIVED_PREEMPT_LINE="    preempt"
    ;;
  master)
    KEEPALIVED_STATE="BACKUP"
    KEEPALIVED_PRIORITY="150"
    HAPROXY_BIND_ADDRESS="*:${HAPROXY_BIND_PORT}"
    KEEPALIVED_ROUTER_NAME="master2"
    KEEPALIVED_UNICAST_SRC_IP="${KEEPALIVED_UNICAST_SRC_IP:-${WIREGUARD_SERVER_IP:-10.0.0.2}}"
    KEEPALIVED_UNICAST_PEERS="${KEEPALIVED_UNICAST_PEERS:-10.0.0.1}"
    KEEPALIVED_PREEMPT_LINE=""
    ;;
  *)
    KEEPALIVED_STATE="BACKUP"
    KEEPALIVED_PRIORITY="100"
    HAPROXY_BIND_ADDRESS="*:${HAPROXY_BIND_PORT}"
    KEEPALIVED_ROUTER_NAME="${ROLE_NAME}"
    KEEPALIVED_UNICAST_SRC_IP="${KEEPALIVED_UNICAST_SRC_IP:-}"
    KEEPALIVED_UNICAST_PEERS="${KEEPALIVED_UNICAST_PEERS:-}"
    KEEPALIVED_PREEMPT_LINE=""
    ;;
esac

ROUTER_ID="51"
VIRTUAL_IP_CIDR="${CONTROL_PLANE_ENDPOINT}/24"

if [[ -z "${CONTROL_PLANE_BACKENDS}" ]]; then
  CONTROL_PLANE_BACKENDS="${KEEPALIVED_UNICAST_SRC_IP},${KEEPALIVED_UNICAST_PEERS}"
fi

if ! [[ "${ROUTER_ID}" =~ ^[0-9]+$ ]] || (( ROUTER_ID < 1 || ROUTER_ID > 255 )); then
  echo "[SERVICES:${ROLE_NAME}] FOUT: KEEPALIVED_ROUTER_ID moet tussen 1 en 255 liggen." >&2
  exit 1
fi

if [[ -z "${KEEPALIVED_UNICAST_SRC_IP}" ]]; then
  echo "[SERVICES:${ROLE_NAME}] FOUT: KEEPALIVED_UNICAST_SRC_IP is leeg." >&2
  exit 1
fi

if [[ -z "${KEEPALIVED_UNICAST_PEERS}" ]]; then
  echo "[SERVICES:${ROLE_NAME}] FOUT: KEEPALIVED_UNICAST_PEERS is leeg." >&2
  exit 1
fi

echo "[SERVICES:${ROLE_NAME}] keepalived + haproxy installeren..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y keepalived haproxy

install -d -m 0755 /etc/linux-server-install
cat > /etc/linux-server-install/control-plane-endpoint <<CFG
CONTROL_PLANE_ENDPOINT=${CONTROL_PLANE_ENDPOINT}
CONTROL_PLANE_BACKENDS=${CONTROL_PLANE_BACKENDS}
KEEPALIVED_INTERFACE=${KEEPALIVED_INTERFACE}
KEEPALIVED_STATE=${KEEPALIVED_STATE}
KEEPALIVED_PRIORITY=${KEEPALIVED_PRIORITY}
CFG
chmod 0644 /etc/linux-server-install/control-plane-endpoint

backend_lines=()
IFS=',' read -r -a backend_ips <<< "${CONTROL_PLANE_BACKENDS}"
for i in "${!backend_ips[@]}"; do
  backend_ip="$(echo "${backend_ips[$i]}" | xargs)"
  if [[ -z "${backend_ip}" ]]; then
    continue
  fi
  backend_lines+=("    server master$((i + 1)) ${backend_ip}:6443 check")
done

if (( ${#backend_lines[@]} == 0 )); then
  echo "[SERVICES:${ROLE_NAME}] FOUT: geen geldige CONTROL_PLANE_BACKENDS gevonden." >&2
  exit 1
fi

unicast_peer_lines=()
IFS=',' read -r -a keepalived_peers <<< "${KEEPALIVED_UNICAST_PEERS}"
for peer_ip in "${keepalived_peers[@]}"; do
  peer_ip="$(echo "${peer_ip}" | xargs)"
  if [[ -z "${peer_ip}" ]]; then
    continue
  fi
  unicast_peer_lines+=("        ${peer_ip}")
done

cat > /etc/haproxy/haproxy.cfg <<CFG
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon

defaults
    log global
    mode tcp
    option tcplog
    timeout connect 5s
    timeout client 60s
    timeout server 60s

frontend k8s_api_frontend
    bind ${HAPROXY_BIND_ADDRESS}
    default_backend k8s_api_backend

backend k8s_api_backend
    option tcp-check
    default-server inter 2s fall 3 rise 2
$(printf '%s
' "${backend_lines[@]}")
CFG

cat > /etc/keepalived/keepalived.conf <<CFG
global_defs {
    router_id LVS_${KEEPALIVED_ROUTER_NAME}
    script_user root
    enable_script_security
}

vrrp_script chk_haproxy {
    script "/usr/bin/pgrep haproxy"
    interval 2
    weight -20
    fall 2
    rise 2
}

vrrp_instance VI_${ROUTER_ID} {
    state ${KEEPALIVED_STATE}
    interface ${KEEPALIVED_INTERFACE}
    virtual_router_id ${ROUTER_ID}
    priority ${KEEPALIVED_PRIORITY}
    advert_int 1

${KEEPALIVED_PREEMPT_LINE}
    unicast_src_ip ${KEEPALIVED_UNICAST_SRC_IP}
    unicast_peer {
$(printf '%s\n' "${unicast_peer_lines[@]}")
    }

    authentication {
        auth_type PASS
        auth_pass 42k8s-lb
    }

    virtual_ipaddress {
        ${VIRTUAL_IP_CIDR}
    }

    track_script {
        chk_haproxy
    }
}
CFG

chmod 0644 /etc/haproxy/haproxy.cfg /etc/keepalived/keepalived.conf

systemctl enable --now haproxy
systemctl enable --now keepalived

echo "[SERVICES:${ROLE_NAME}] Endpoint vastgelegd op ${CONTROL_PLANE_ENDPOINT}."
echo "[SERVICES:${ROLE_NAME}] keepalived en haproxy geconfigureerd en gestart."
echo "[SERVICES:${ROLE_NAME}] Klaar."
