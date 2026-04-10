#!/usr/bin/env bash
set -euo pipefail

MICHAEL_USER="${MICHAEL_USER:-michael}"
MICHAEL_KEY="${MICHAEL_KEY:-ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAmp04tIimmABx6bUEA29zvJ2IaeyWWAJFOWnN0YELT9 eddsa-key-20260401}"
SSH_PORT="${SSH_PORT:-40111}"
WIREGUARD_PORT="${WIREGUARD_PORT:-51820}"
ALLOWED_SSH_IPS="${ALLOWED_SSH_IPS:-188.207.111.246,145.53.102.212}"
IPV6_POLICY="${IPV6_POLICY:-drop}"
AUTO_REBOOT="${AUTO_REBOOT:-false}"
BOOTSTRAP_MASTER="${BOOTSTRAP_MASTER:-auto}"

# Backward compatibility voor oudere scripts die ALLOWED_IP_1/2 gebruiken.
ALLOWED_IP_1="${ALLOWED_IP_1:-188.207.111.246}"
ALLOWED_IP_2="${ALLOWED_IP_2:-145.53.102.212}"

parse_csv_to_array() {
  local csv_input="${1:-}"
  local -n out_ref="$2"

  out_ref=()
  IFS=',' read -r -a raw_values <<< "${csv_input}"
  for raw in "${raw_values[@]}"; do
    local trimmed
    trimmed="$(echo "${raw}" | xargs)"
    [[ -n "${trimmed}" ]] && out_ref+=("${trimmed}")
  done
}

is_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

export DEBIAN_FRONTEND=noninteractive
