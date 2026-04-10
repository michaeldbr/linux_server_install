#!/usr/bin/env bash
set -euo pipefail

install_haproxy_if_needed() {
  if command -v haproxy >/dev/null 2>&1; then
    return 0
  fi

  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y haproxy
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y haproxy
  elif command -v yum >/dev/null 2>&1; then
    yum install -y haproxy
  else
    echo "Geen ondersteunde package manager gevonden voor HAProxy." >&2
    exit 1
  fi
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
  option dontlognull
  timeout connect 5s
  timeout client 50s
  timeout server 50s

frontend k8s
  bind 127.0.0.1:6443
  mode tcp
  default_backend masters

backend masters
  mode tcp
  option tcp-check
  server master1 10.0.0.1:6443 check
  server master2 10.0.0.2:6443 check
  server master3 10.0.0.3:6443 check
CFG

  systemctl enable --now haproxy
  systemctl restart haproxy
}

install_haproxy_if_needed
configure_hosts
configure_haproxy

echo "HAProxy master-config toegepast."
