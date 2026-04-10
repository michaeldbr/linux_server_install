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
    master|worker|traffic) return 0 ;;
    *) return 1 ;;
  esac
}

validate_role_choice() {
  local role_choice="${1:-}"
  case "${role_choice}" in
    1|2|3) return 0 ;;
    *) return 1 ;;
  esac
}

role_from_choice() {
  local role_choice="${1:-}"
  case "${role_choice}" in
    1) printf 'master' ;;
    2) printf 'worker' ;;
    3) printf 'traffic' ;;
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

validate_non_interactive_input() {
  local ip="${WIREGUARD_SERVER_IP:-}"
  local role="${SERVER_ROLE:-}"
  local hostname="${TARGET_HOSTNAME:-}"

  [[ -n "${ip}" && -n "${role}" && -n "${hostname}" ]] || return 1
  validate_internal_ip "${ip}" || return 1
  validate_role "${role}" || return 1
  validate_hostname "${hostname}" || return 1
}

collect_install_input() {
  local tty_fd

  if validate_non_interactive_input; then
    echo "[PRE-FLIGHT] Non-interactive input gedetecteerd via environment variables."
    export WIREGUARD_SERVER_IP SERVER_ROLE TARGET_HOSTNAME
    return 0
  fi

  if [[ "${INSTALL_NON_INTERACTIVE:-false}" == "true" ]]; then
    echo "[PRE-FLIGHT] FOUT: INSTALL_NON_INTERACTIVE=true maar input is onvolledig/ongeldig." >&2
    echo "[PRE-FLIGHT] Vereist: WIREGUARD_SERVER_IP, SERVER_ROLE (master|worker|traffic), TARGET_HOSTNAME." >&2
    return 1
  fi

  if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
    echo "[PRE-FLIGHT] FOUT: Interactieve input is niet mogelijk (/dev/tty ontbreekt)." >&2
    echo "[PRE-FLIGHT] Geef non-interactive input mee via env vars." >&2
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
  echo "  1) master" >&"${tty_fd}"
  echo "  2) worker" >&"${tty_fd}"
  echo "  3) traffic" >&"${tty_fd}"

  local role_choice
  role_choice="$(prompt_with_confirmation "${tty_fd}" \
    "Voer rolnummer in (1-3): " \
    "Voer hetzelfde rolnummer opnieuw in ter bevestiging: " \
    validate_role_choice \
    "[PRE-FLIGHT] Ongeldig rolnummer. Kies: 1, 2 of 3.")"
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
