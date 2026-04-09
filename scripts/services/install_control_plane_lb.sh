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

echo "[SERVICES:${ROLE_NAME}] haproxy installeren..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y haproxy

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

install -d -m 0755 /etc/linux-server-install
cat > /etc/linux-server-install/control-plane-endpoint <<CFG
CONTROL_PLANE_ENDPOINT=${CONTROL_PLANE_ENDPOINT}
CONTROL_PLANE_BACKENDS=${CONTROL_PLANE_BACKENDS}
HAPROXY_BIND_PORT=${HAPROXY_BIND_PORT}
CFG
chmod 0644 /etc/linux-server-install/control-plane-endpoint

echo "[SERVICES:${ROLE_NAME}] Endpoint vastgelegd op ${CONTROL_PLANE_ENDPOINT}."
echo "[SERVICES:${ROLE_NAME}] haproxy geconfigureerd en gestart."
echo "[SERVICES:${ROLE_NAME}] Klaar."
