#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${LETSENCRYPT_DOMAIN:-}" || -z "${LETSENCRYPT_EMAIL:-}" ]]; then
  echo "LETSENCRYPT_DOMAIN of LETSENCRYPT_EMAIL ontbreekt." >&2
  exit 1
fi

install_certbot() {
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y certbot python3-certbot-apache
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y certbot python3-certbot-apache
  elif command -v yum >/dev/null 2>&1; then
    yum install -y certbot python3-certbot-apache
  else
    echo "Geen ondersteunde package manager gevonden om certbot te installeren." >&2
    exit 1
  fi
}

request_certificate() {
  certbot --apache \
    --non-interactive \
    --agree-tos \
    --email "$LETSENCRYPT_EMAIL" \
    --domains "$LETSENCRYPT_DOMAIN" \
    --redirect
}

enable_auto_renew() {
  if systemctl list-unit-files | grep -q '^certbot\.timer'; then
    systemctl enable --now certbot.timer
  elif [[ -x /usr/bin/certbot ]]; then
    (crontab -l 2>/dev/null; echo '15 3 * * * certbot renew --quiet') | sort -u | crontab -
  fi
}

install_certbot
request_certificate
enable_auto_renew

echo "Let's Encrypt certificaat aangevraagd, geïnstalleerd en auto-renew geconfigureerd."
