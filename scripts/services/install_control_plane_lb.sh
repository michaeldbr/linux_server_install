#!/usr/bin/env bash
set -euo pipefail

ROLE_NAME="${1:-}"
CONTROL_PLANE_ENDPOINT="${2:-}"
CONTROL_PLANE_BACKENDS="${CONTROL_PLANE_BACKENDS:-}"
HAPROXY_BIND_PORT="${HAPROXY_BIND_PORT:-7443}"
KEEPALIVED_ENABLED="${KEEPALIVED_ENABLED:-true}"
KEEPALIVED_INTERFACE="${KEEPALIVED_INTERFACE:-}"
KEEPALIVED_ROUTER_ID="${KEEPALIVED_ROUTER_ID:-51}"
KEEPALIVED_PRIORITY="${KEEPALIVED_PRIORITY:-}"
KEEPALIVED_AUTH_PASS="${KEEPALIVED_AUTH_PASS:-K8sHA001}"
KEEPALIVED_STATE="${KEEPALIVED_STATE:-}"
KEEPALIVED_LOCAL_IP="${KEEPALIVED_LOCAL_IP:-${WIREGUARD_SERVER_IP:-}}"

if [[ -z "${ROLE_NAME}" ]]; then
  echo "[SERVICES] FOUT: role argument ontbreekt." >&2
  exit 1
fi

if [[ -z "${CONTROL_PLANE_ENDPOINT}" ]]; then
  echo "[SERVICES] FOUT: control plane endpoint ontbreekt." >&2
  exit 1
fi

case "${ROLE_NAME}" in
  master)
    DEFAULT_BACKEND_IP="10.0.0.1,10.0.0.2,10.0.0.3"
    ;;
  *)
    DEFAULT_BACKEND_IP="${WIREGUARD_SERVER_IP:-}"
    ;;
esac

if [[ -z "${CONTROL_PLANE_BACKENDS}" ]]; then
  CONTROL_PLANE_BACKENDS="${DEFAULT_BACKEND_IP}"
fi

if [[ -z "${CONTROL_PLANE_BACKENDS//,/}" ]]; then
  echo "[SERVICES:${ROLE_NAME}] FOUT: CONTROL_PLANE_BACKENDS is leeg." >&2
  exit 1
fi

detect_keepalived_interface() {
  if [[ -n "${KEEPALIVED_INTERFACE}" ]]; then
    echo "${KEEPALIVED_INTERFACE}"
    return 0
  fi

  if ip link show wg0 >/dev/null 2>&1; then
    echo "wg0"
    return 0
  fi

  local inferred_iface
  inferred_iface="$(ip -o route get "${CONTROL_PLANE_ENDPOINT}" 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i == "dev") {print $(i+1); exit}}')"
  if [[ -n "${inferred_iface}" ]]; then
    echo "${inferred_iface}"
    return 0
  fi

  inferred_iface="$(ip -o link show | awk -F': ' '$2 != "lo" {print $2; exit}')"
  if [[ -n "${inferred_iface}" ]]; then
    echo "${inferred_iface}"
    return 0
  fi

  echo "lo"
}

derive_keepalived_defaults() {
  local local_index=-1
  local i
  for i in "${!backend_ips[@]}"; do
    local candidate_ip
    candidate_ip="$(echo "${backend_ips[$i]}" | xargs)"
    if [[ -n "${candidate_ip}" && "${candidate_ip}" == "${KEEPALIVED_LOCAL_IP}" ]]; then
      local_index="${i}"
      break
    fi
  done

  if (( local_index < 0 )); then
    echo "[SERVICES:${ROLE_NAME}] FOUT: KEEPALIVED_LOCAL_IP (${KEEPALIVED_LOCAL_IP}) staat niet in CONTROL_PLANE_BACKENDS (${CONTROL_PLANE_BACKENDS})." >&2
    exit 1
  fi

  if [[ -z "${KEEPALIVED_STATE}" ]]; then
    if (( local_index == 0 )); then
      KEEPALIVED_STATE="MASTER"
    else
      KEEPALIVED_STATE="BACKUP"
    fi
  fi

  if [[ -z "${KEEPALIVED_PRIORITY}" ]]; then
    local derived_priority=$((150 - (local_index * 10)))
    if (( derived_priority < 50 )); then
      derived_priority=50
    fi
    KEEPALIVED_PRIORITY="${derived_priority}"
  fi
}

if [[ "${KEEPALIVED_ENABLED}" == "true" ]]; then
  echo "[SERVICES:${ROLE_NAME}] haproxy en keepalived installeren..."
else
  echo "[SERVICES:${ROLE_NAME}] haproxy installeren..."
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
if [[ "${KEEPALIVED_ENABLED}" == "true" ]]; then
  apt-get install -y haproxy keepalived
else
  apt-get install -y haproxy
fi

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
    bind *:${HAPROXY_BIND_PORT}
    default_backend k8s_api_backend

backend k8s_api_backend
    option tcp-check
    default-server inter 2s fall 3 rise 2
$(printf '%s
' "${backend_lines[@]}")
CFG

chmod 0644 /etc/haproxy/haproxy.cfg
systemctl enable --now haproxy

if [[ "${KEEPALIVED_ENABLED}" == "true" ]]; then
  resolved_keepalived_interface="$(detect_keepalived_interface)"
  if [[ -z "${KEEPALIVED_INTERFACE}" ]]; then
    KEEPALIVED_INTERFACE="${resolved_keepalived_interface}"
  fi

  if [[ -z "${KEEPALIVED_LOCAL_IP}" ]]; then
    echo "[SERVICES:${ROLE_NAME}] FOUT: KEEPALIVED_LOCAL_IP is leeg. Zet KEEPALIVED_LOCAL_IP of WIREGUARD_SERVER_IP." >&2
    exit 1
  fi

  derive_keepalived_defaults
fi

install -d -m 0755 /etc/linux-server-install
cat > /etc/linux-server-install/control-plane-endpoint <<CFG
CONTROL_PLANE_ENDPOINT=${CONTROL_PLANE_ENDPOINT}
CONTROL_PLANE_BACKENDS=${CONTROL_PLANE_BACKENDS}
HAPROXY_BIND_PORT=${HAPROXY_BIND_PORT}
KEEPALIVED_ENABLED=${KEEPALIVED_ENABLED}
KEEPALIVED_INTERFACE=${KEEPALIVED_INTERFACE}
KEEPALIVED_LOCAL_IP=${KEEPALIVED_LOCAL_IP}
KEEPALIVED_ROUTER_ID=${KEEPALIVED_ROUTER_ID}
KEEPALIVED_STATE=${KEEPALIVED_STATE}
KEEPALIVED_PRIORITY=${KEEPALIVED_PRIORITY}
CFG
chmod 0644 /etc/linux-server-install/control-plane-endpoint

if [[ "${KEEPALIVED_ENABLED}" == "true" ]]; then
  keepalived_peer_lines=()
  for backend_ip in "${backend_ips[@]}"; do
    peer_ip="$(echo "${backend_ip}" | xargs)"
    if [[ -z "${peer_ip}" || "${peer_ip}" == "${KEEPALIVED_LOCAL_IP}" ]]; then
      continue
    fi
    keepalived_peer_lines+=("        ${peer_ip}")
  done

  unicast_block=""
  if (( ${#keepalived_peer_lines[@]} > 0 )); then
    unicast_block="    unicast_src_ip ${KEEPALIVED_LOCAL_IP}
    unicast_peer {
$(printf '%s\n' "${keepalived_peer_lines[@]}")
    }"
  fi

  if [[ ${#KEEPALIVED_AUTH_PASS} -gt 8 ]]; then
    KEEPALIVED_AUTH_PASS="${KEEPALIVED_AUTH_PASS:0:8}"
  fi

  cat > /etc/keepalived/keepalived.conf <<CFG
global_defs {
    router_id ${ROLE_NAME}_$(hostname -s)
}

vrrp_script chk_haproxy {
    script "pidof haproxy"
    interval 2
    fall 2
    rise 2
}

vrrp_instance VI_K8S_API {
    state ${KEEPALIVED_STATE}
    interface ${KEEPALIVED_INTERFACE}
    virtual_router_id ${KEEPALIVED_ROUTER_ID}
    priority ${KEEPALIVED_PRIORITY}
    advert_int 1
${unicast_block}
    authentication {
        auth_type PASS
        auth_pass ${KEEPALIVED_AUTH_PASS}
    }
    virtual_ipaddress {
        ${CONTROL_PLANE_ENDPOINT}/32 dev ${KEEPALIVED_INTERFACE}
    }
    track_script {
        chk_haproxy
    }
}
CFG

  chmod 0644 /etc/keepalived/keepalived.conf
  systemctl enable --now keepalived
fi

echo "[SERVICES:${ROLE_NAME}] Endpoint vastgelegd op ${CONTROL_PLANE_ENDPOINT}."
echo "[SERVICES:${ROLE_NAME}] haproxy geconfigureerd en gestart."
if [[ "${KEEPALIVED_ENABLED}" == "true" ]]; then
  echo "[SERVICES:${ROLE_NAME}] keepalived geconfigureerd en gestart (${KEEPALIVED_STATE}, priority=${KEEPALIVED_PRIORITY}, iface=${KEEPALIVED_INTERFACE})."
fi
echo "[SERVICES:${ROLE_NAME}] Klaar."
