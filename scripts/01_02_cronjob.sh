#!/usr/bin/env bash
set -euo pipefail

install_cron_if_needed() {
  if command -v crontab >/dev/null 2>&1; then
    return 0
  fi

  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y cron
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y cronie
  elif command -v yum >/dev/null 2>&1; then
    yum install -y cronie
  else
    echo "Geen ondersteunde package manager gevonden om cron te installeren." >&2
    exit 1
  fi
}

enable_cron_service() {
  if systemctl list-unit-files | grep -q '^cron\.service'; then
    systemctl enable --now cron
  elif systemctl list-unit-files | grep -q '^crond\.service'; then
    systemctl enable --now crond
  else
    echo "Cron service niet gevonden (cron/crond)." >&2
    exit 1
  fi
}

install_cron_if_needed
enable_cron_service

echo "Cronjob service installatie gereed."
