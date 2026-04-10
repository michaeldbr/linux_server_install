#!/usr/bin/env bash
set -euo pipefail

FLUENTBIT_HOST="${FLUENTBIT_HOST:-10.0.0.1}"
FLUENTBIT_PORT="${FLUENTBIT_PORT:-24224}"

install_fluentbit_if_needed() {
  if command -v fluent-bit >/dev/null 2>&1; then
    return 0
  fi

  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y fluent-bit
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y fluent-bit
  elif command -v yum >/dev/null 2>&1; then
    yum install -y fluent-bit
  else
    echo "Geen ondersteunde package manager gevonden voor Fluent Bit." >&2
    exit 1
  fi
}

configure_fluentbit() {
  mkdir -p /etc/fluent-bit

  cat > /etc/fluent-bit/fluent-bit.conf <<CFG
[SERVICE]
    Flush        1
    Daemon       Off
    Log_Level    info

[INPUT]
    Name              systemd
    Tag               systemd.*
    Systemd_Filter    _SYSTEMD_UNIT=iptables.service
    Read_From_Tail    On

[INPUT]
    Name              systemd
    Tag               journald.*
    Read_From_Tail    On

[OUTPUT]
    Name              forward
    Match             *
    Host              ${FLUENTBIT_HOST}
    Port              ${FLUENTBIT_PORT}
CFG

  systemctl enable --now fluent-bit
  systemctl restart fluent-bit
}

install_fluentbit_if_needed
configure_fluentbit

echo "Fluent Bit geïnstalleerd en geconfigureerd naar ${FLUENTBIT_HOST}:${FLUENTBIT_PORT}."
