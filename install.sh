#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Dit script moet als root worden uitgevoerd." >&2
  exit 1
fi

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_SCRIPT="${BASE_DIR}/scripts/01_ssh/install_ssh.sh"
FIREWALL_SCRIPT="${BASE_DIR}/scripts/02_firewall/install_firewall.sh"
WIREGUARD_SCRIPT="${BASE_DIR}/scripts/03_wireguard/install_wireguard.sh"

ask_twice_match() {
  local prompt="$1"
  local first second

  while true; do
    read -r -p "$prompt" first
    read -r -p "Herhaal ter controle: " second

    if [[ "$first" == "$second" && -n "$first" ]]; then
      printf '%s' "$first"
      return 0
    fi

    echo "Antwoorden komen niet overeen of zijn leeg. Probeer opnieuw."
  done
}

is_valid_ip() {
  local ip="$1"
  local IFS='.'
  local -a octets

  read -r -a octets <<< "$ip"
  [[ ${#octets[@]} -eq 4 ]] || return 1

  for o in "${octets[@]}"; do
    [[ "$o" =~ ^[0-9]{1,3}$ ]] || return 1
    (( o >= 0 && o <= 255 )) || return 1
  done

  return 0
}

ask_internal_ip() {
  local ip
  while true; do
    ip="$(ask_twice_match 'Wat is het interne IP-adres van de server? ')"
    if is_valid_ip "$ip"; then
      printf '%s' "$ip"
      return 0
    fi
    echo "Ongeldig IP-adres formaat. Probeer opnieuw."
  done
}

ask_role() {
  local role_choice
  while true; do
    echo "Kies de role:"
    echo "1) master"
    echo "2) worker"
    role_choice="$(ask_twice_match 'Voer 1 of 2 in: ')"

    case "$role_choice" in
      1)
        printf 'master'
        return 0
        ;;
      2)
        printf 'worker'
        return 0
        ;;
      *)
        echo "Ongeldige keuze. Kies 1 of 2."
        ;;
    esac
  done
}

ask_hostname() {
  local host
  while true; do
    host="$(ask_twice_match 'Wat moet de hostname zijn? ')"
    if [[ "$host" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
      printf '%s' "$host"
      return 0
    fi
    echo "Ongeldige hostname. Gebruik letters, cijfers en koppelteken (max 63 tekens)."
  done
}

if [[ ! -x "$SSH_SCRIPT" ]]; then
  echo "Kan SSH script niet uitvoeren: $SSH_SCRIPT" >&2
  exit 1
fi

if [[ ! -x "$FIREWALL_SCRIPT" ]]; then
  echo "Kan firewall script niet uitvoeren: $FIREWALL_SCRIPT" >&2
  exit 1
fi

if [[ ! -x "$WIREGUARD_SCRIPT" ]]; then
  echo "Kan WireGuard script niet uitvoeren: $WIREGUARD_SCRIPT" >&2
  exit 1
fi

INTERNAL_IP="$(ask_internal_ip)"
ROLE="$(ask_role)"
HOSTNAME_VALUE="$(ask_hostname)"

echo "Gekozen intern IP: ${INTERNAL_IP}"
echo "Gekozen role: ${ROLE}"
echo "Gekozen hostname: ${HOSTNAME_VALUE}"

echo "Hostname instellen..."
hostnamectl set-hostname "$HOSTNAME_VALUE"

echo "$ROLE" > /etc/linux_server_role
echo "Role opgeslagen in /etc/linux_server_role"

"$SSH_SCRIPT"
"$FIREWALL_SCRIPT"
"$WIREGUARD_SCRIPT"

echo "Installatie afgerond."
