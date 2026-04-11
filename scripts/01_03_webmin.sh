#!/usr/bin/env bash
set -euo pipefail

WEBMIN_PORT="40112"

install_webmin_debian() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl gnupg apt-transport-https software-properties-common

  if [[ ! -f /usr/share/keyrings/webmin.gpg ]]; then
    curl -fsSL https://download.webmin.com/jcameron-key.asc | gpg --dearmor -o /usr/share/keyrings/webmin.gpg
  fi

  cat > /etc/apt/sources.list.d/webmin.list <<'SRC'
deb [signed-by=/usr/share/keyrings/webmin.gpg] https://download.webmin.com/download/repository sarge contrib
SRC

  apt-get update -y
  apt-get install -y webmin
}

install_webmin_rhel() {
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y curl gnupg2
  else
    yum install -y curl gnupg2
  fi

  cat > /etc/yum.repos.d/webmin.repo <<'REPO'
[Webmin]
name=Webmin Distribution Neutral
baseurl=https://download.webmin.com/download/yum
enabled=1
gpgcheck=1
gpgkey=https://download.webmin.com/jcameron-key.asc
REPO

  if command -v dnf >/dev/null 2>&1; then
    dnf install -y webmin
  else
    yum install -y webmin
  fi
}

configure_webmin_port() {
  local conf="/etc/webmin/miniserv.conf"

  if [[ ! -f "$conf" ]]; then
    echo "Webmin configuratiebestand niet gevonden: $conf" >&2
    exit 1
  fi

  if grep -q '^port=' "$conf"; then
    sed -i "s/^port=.*/port=${WEBMIN_PORT}/" "$conf"
  else
    echo "port=${WEBMIN_PORT}" >> "$conf"
  fi
}

if command -v apt-get >/dev/null 2>&1; then
  install_webmin_debian
elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
  install_webmin_rhel
else
  echo "Geen ondersteunde package manager voor Webmin installatie." >&2
  exit 1
fi

configure_webmin_port

if systemctl list-unit-files | grep -q '^webmin\.service'; then
  systemctl enable --now webmin
  systemctl restart webmin
else
  echo "Webmin service niet gevonden na installatie." >&2
  exit 1
fi

echo "Webmin geïnstalleerd en ingesteld op poort ${WEBMIN_PORT}."
