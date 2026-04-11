#!/usr/bin/env bash
set -euo pipefail

ensure_haproxy_present() {
  if command -v haproxy >/dev/null 2>&1; then
    return 0
  fi

  echo "HAProxy is niet geïnstalleerd; installatie wordt bewust overgeslagen." >&2
  echo "Installeer HAProxy handmatig en draai dit script opnieuw." >&2
  exit 1
}

configure_hosts() {
  if ! grep -qE '^127\.0\.0\.1[[:space:]]+k8s-api\.internal(\s|$)' /etc/hosts; then
    echo "127.0.0.1 k8s-api.internal" >> /etc/hosts
  fi
}

configure_haproxy() {
  if [[ -f /etc/haproxy/haproxy.cfg ]] && grep -q "k8s-api.internal" /etc/haproxy/haproxy.cfg; then
    echo "Bestaande HAProxy config lijkt al correct; overslaan."
    systemctl enable --now haproxy
    systemctl restart haproxy
    return 0
  fi

  cat > /etc/haproxy/haproxy.cfg <<'CFG'
global
  log /dev/log local0
  log /dev/log local1 notice
  daemon

defaults
  log global
  mode tcp
  option tcplog
  timeout connect 5s
  timeout client  60s
  timeout server  60s

frontend k8s
  bind 0.0.0.0:7443
  mode tcp
  default_backend masters

backend masters
  mode tcp
  option tcp-check
  default-server inter 3s fall 3 rise 2

  server master1 10.0.0.1:6443 check
  server master2 10.0.0.2:6443 check
  server master3 10.0.0.3:6443 check
CFG

  systemctl enable --now haproxy
  systemctl restart haproxy
}

ensure_haproxy_present
configure_hosts
configure_haproxy

echo "HAProxy master-config toegepast."
