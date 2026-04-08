#!/usr/bin/env bash
set -euo pipefail

validate_internal_ip() {
  local ip="${1:-}"

  if [[ ! "${ip}" =~ ^10\.0\.0\.[0-9]{1,3}$ ]]; then
    return 1
  fi

  local last_octet="${ip##*.}"
  (( last_octet >= 1 && last_octet <= 254 ))
}

validate_role() {
  local role="${1:-}"
  case "${role}" in
    first-master|master|worker|traffic) return 0 ;;
    *) return 1 ;;
  esac
}

validate_role_choice() {
  local role_choice="${1:-}"
  case "${role_choice}" in
    1|2|3|4) return 0 ;;
    *) return 1 ;;
  esac
}

role_from_choice() {
  local role_choice="${1:-}"
  case "${role_choice}" in
    1) printf 'first-master' ;;
    2) printf 'master' ;;
    3) printf 'worker' ;;
    4) printf 'traffic' ;;
    *) return 1 ;;
  esac
}

validate_hostname() {
  local hostname="${1:-}"
  [[ "${hostname}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]
}

prompt_with_confirmation() {
  local tty_fd="$1"
  local prompt="$2"
  local confirm_prompt="$3"
  local validate_fn="$4"
  local error_msg="$5"
  local first_value
  local second_value

  while true; do
    read -r -u "${tty_fd}" -p "${prompt}" first_value

    if ! "${validate_fn}" "${first_value}"; then
      echo "${error_msg}" >&"${tty_fd}"
      continue
    fi

    read -r -u "${tty_fd}" -p "${confirm_prompt}" second_value
    if [[ "${second_value}" != "${first_value}" ]]; then
      echo "[PRE-FLIGHT] Waarden komen niet overeen, probeer opnieuw." >&"${tty_fd}"
      continue
    fi

    printf '%s' "${first_value}"
    return 0
  done
}

collect_install_input() {
  local tty_fd

  if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
    echo "[PRE-FLIGHT] FOUT: Interactieve input is niet mogelijk (/dev/tty ontbreekt)." >&2
    return 1
  fi

  exec {tty_fd}<>/dev/tty

  echo "[PRE-FLIGHT] Interne server gegevens verzamelen..." >&"${tty_fd}"

  WIREGUARD_SERVER_IP="$(prompt_with_confirmation "${tty_fd}" \
    "Voer het interne IP in (bijv. 10.0.0.2): " \
    "Voer het interne IP opnieuw in ter bevestiging: " \
    validate_internal_ip \
    "[PRE-FLIGHT] Ongeldig IP. Gebruik formaat 10.0.0.X waarbij X tussen 1 en 254 ligt.")"

  echo "[PRE-FLIGHT] Kies een rolnummer:" >&"${tty_fd}"
  echo "  1) first-master" >&"${tty_fd}"
  echo "  2) master" >&"${tty_fd}"
  echo "  3) worker" >&"${tty_fd}"
  echo "  4) traffic" >&"${tty_fd}"

  local role_choice
  role_choice="$(prompt_with_confirmation "${tty_fd}" \
    "Voer rolnummer in (1-4): " \
    "Voer hetzelfde rolnummer opnieuw in ter bevestiging: " \
    validate_role_choice \
    "[PRE-FLIGHT] Ongeldig rolnummer. Kies: 1, 2, 3 of 4.")"
  SERVER_ROLE="$(role_from_choice "${role_choice}")"
  validate_role "${SERVER_ROLE}"

  TARGET_HOSTNAME="$(prompt_with_confirmation "${tty_fd}" \
    "Voer hostnaam in: " \
    "Voer dezelfde hostnaam opnieuw in ter bevestiging: " \
    validate_hostname \
    "[PRE-FLIGHT] Ongeldige hostnaam. Gebruik letters, cijfers en koppeltekens (max 63 tekens).")"

  exec {tty_fd}>&-

  export WIREGUARD_SERVER_IP
  export SERVER_ROLE
  export TARGET_HOSTNAME
}
