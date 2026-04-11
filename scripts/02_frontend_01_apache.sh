#!/usr/bin/env bash
set -euo pipefail

APACHE_MODULES=(
  access_compat
  alias
  dir
  mime
  setenvif
  deflate
  filter
  headers
  ssl
  http2
  rewrite
)

install_apache() {
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y apache2
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y httpd mod_ssl
  elif command -v yum >/dev/null 2>&1; then
    yum install -y httpd mod_ssl
  else
    echo "Geen ondersteunde package manager gevonden om Apache te installeren." >&2
    exit 1
  fi
}

enable_apache_service() {
  if systemctl list-unit-files | grep -q '^apache2\.service'; then
    systemctl enable --now apache2
  elif systemctl list-unit-files | grep -q '^httpd\.service'; then
    systemctl enable --now httpd
  else
    echo "Apache service niet gevonden (apache2/httpd)." >&2
    exit 1
  fi
}

enable_apache_modules() {
  if command -v a2enmod >/dev/null 2>&1; then
    a2enmod "${APACHE_MODULES[@]}"
    systemctl restart apache2
  else
    echo "a2enmod niet beschikbaar; modules worden via distro-defaults beheerd." >&2
  fi
}

install_apache
enable_apache_service
enable_apache_modules

echo "Apache installatie gereed voor frontend role."
