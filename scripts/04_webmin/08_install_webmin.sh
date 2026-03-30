#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/00_common/common.sh
source "${SCRIPT_DIR}/../00_common/common.sh"

if ! command -v apt-get >/dev/null 2>&1; then
  echo "Alleen Debian/Ubuntu (apt-get) wordt ondersteund voor Webmin installatie." >&2
  exit 1
fi

install_webmin_repo() {
  DEBIAN_FRONTEND=noninteractive apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg apt-transport-https

  install -d -m 0755 /usr/share/keyrings
  curl -fsSL https://download.webmin.com/developers-key.asc \
    | gpg --dearmor -o /usr/share/keyrings/webmin-archive-keyring.gpg

  cat > /etc/apt/sources.list.d/webmin.list <<'LIST'
deb [signed-by=/usr/share/keyrings/webmin-archive-keyring.gpg] https://download.webmin.com/download/newkey/repository stable contrib
LIST

  DEBIAN_FRONTEND=noninteractive apt-get update
}

get_webmin_password() {
  local pass1 pass2

  if [[ -n "${WEBMIN_PASSWORD:-}" ]]; then
    echo "WEBMIN_PASSWORD gevonden in environment; interactieve prompt overgeslagen."
    printf '%s' "${WEBMIN_PASSWORD}"
    return 0
  fi

  if [[ ! -r /dev/tty ]]; then
    echo "Geen interactieve TTY beschikbaar. Zet WEBMIN_PASSWORD om door te gaan." >&2
    exit 1
  fi

  while true; do
    read -r -s -p "Voer Webmin wachtwoord in voor gebruiker '${MICHAEL_USER}': " pass1 < /dev/tty
    echo > /dev/tty
    read -r -s -p "Herhaal wachtwoord: " pass2 < /dev/tty
    echo > /dev/tty

    if [[ -z "${pass1}" ]]; then
      echo "Wachtwoord mag niet leeg zijn." > /dev/tty
      continue
    fi

    if [[ "${pass1}" != "${pass2}" ]]; then
      echo "Wachtwoorden komen niet overeen, probeer opnieuw." > /dev/tty
      continue
    fi

    printf '%s' "${pass1}"
    return 0
  done
}

configure_webmin_port() {
  if grep -qE '^port=' /etc/webmin/miniserv.conf; then
    sed -i "s/^port=.*/port=${WEBMIN_PORT}/" /etc/webmin/miniserv.conf
  else
    echo "port=${WEBMIN_PORT}" >> /etc/webmin/miniserv.conf
  fi
}

install_webmin_repo
DEBIAN_FRONTEND=noninteractive apt-get install -y webmin

webmin_password="$(get_webmin_password)"
/usr/share/webmin/changepass.pl /etc/webmin "${MICHAEL_USER}" "${webmin_password}"
unset webmin_password

configure_webmin_port
systemctl restart webmin
systemctl enable webmin
