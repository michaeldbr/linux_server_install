#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Dit script moet als root worden uitgevoerd (bijv. met sudo)." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "[1/2] Systeem pakketlijsten verversen..."
apt-get update

echo "[2/2] Volledige systeemupdate uitvoeren..."
apt-get -y full-upgrade

echo "Opschonen van ongebruikte pakketten..."
apt-get -y autoremove --purge
apt-get -y autoclean

echo "Systeemupdate is voltooid."
