#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Dit script moet als root worden uitgevoerd." >&2
  exit 1
fi

REPO_URL="${REPO_URL:-https://github.com/michaeldbr/linux_server_install.git}"
BRANCH="${BRANCH:-main}"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_REPO_DIR=""

install_git_if_needed() {
  if command -v git >/dev/null 2>&1; then
    return 0
  fi

  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y git
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y git
  elif command -v yum >/dev/null 2>&1; then
    yum install -y git
  else
    echo "Git ontbreekt en kon niet automatisch worden geïnstalleerd." >&2
    exit 1
  fi
}

cleanup() {
  if [[ -n "$TMP_REPO_DIR" && -d "$TMP_REPO_DIR" ]]; then
    rm -rf "$TMP_REPO_DIR"
  fi
}
trap cleanup EXIT

fetch_scripts_if_needed() {
  local ssh_script_local="${BASE_DIR}/scripts/01_ssh/install_ssh.sh"
  local firewall_script_local="${BASE_DIR}/scripts/02_firewall/install_firewall.sh"
  local wg_script_local="${BASE_DIR}/scripts/03_wireguard/install_wireguard.sh"
  local k8s_script_local="${BASE_DIR}/scripts/04_kubernetes/install_kubernetes.sh"
  local master_script_local="${BASE_DIR}/scripts/05_master/setup_master.sh"

  if [[ -x "$ssh_script_local" && -x "$firewall_script_local" && -x "$wg_script_local" && -x "$k8s_script_local" && -x "$master_script_local" ]]; then
    echo "$BASE_DIR"
    return 0
  fi

  echo "Lokale scripts niet gevonden. Repo wordt opgehaald vanuit: ${REPO_URL} (branch: ${BRANCH})"
  install_git_if_needed

  TMP_REPO_DIR="$(mktemp -d)"
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TMP_REPO_DIR"

  if [[ ! -x "$TMP_REPO_DIR/scripts/01_ssh/install_ssh.sh" || ! -x "$TMP_REPO_DIR/scripts/02_firewall/install_firewall.sh" || ! -x "$TMP_REPO_DIR/scripts/03_wireguard/install_wireguard.sh" || ! -x "$TMP_REPO_DIR/scripts/04_kubernetes/install_kubernetes.sh" || ! -x "$TMP_REPO_DIR/scripts/05_master/setup_master.sh" ]]; then
    echo "Vereiste scripts ontbreken in de opgehaalde repository." >&2
    exit 1
  fi

  echo "$TMP_REPO_DIR"
}

retry() {
  local attempts="$1"
  local delay="$2"
  shift 2

  local i
  for ((i=1; i<=attempts; i++)); do
    if "$@"; then
      return 0
    fi
    sleep "$delay"
  done

  return 1
}

check_network_ready() {
  echo "Controle netwerkbereikbaarheid..."

  if ! retry 10 3 getent hosts pkgs.k8s.io >/dev/null 2>&1; then
    echo "Netwerk/DNS niet klaar: pkgs.k8s.io kan niet worden resolved." >&2
    exit 1
  fi

  if ! retry 10 3 ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
    echo "Netwerk niet klaar: geen internet connectiviteit naar 1.1.1.1." >&2
    exit 1
  fi
}

check_wireguard_ready() {
  echo "Controle WireGuard status..."

  if ! retry 10 3 systemctl is-active --quiet wg-quick@wg0; then
    echo "WireGuard service wg-quick@wg0 is niet actief." >&2
    exit 1
  fi

  if ! retry 10 3 wg show wg0 >/dev/null 2>&1; then
    echo "WireGuard interface wg0 is niet beschikbaar." >&2
    exit 1
  fi
}

check_kubelet_healthy() {
  echo "Controle kubelet health..."

  if ! retry 20 3 systemctl is-active --quiet kubelet; then
    echo "kubelet service is niet actief." >&2
    exit 1
  fi

  if command -v curl >/dev/null 2>&1; then
    if ! retry 20 3 curl -fsS http://127.0.0.1:10248/healthz >/dev/null 2>&1; then
      echo "kubelet health endpoint is niet healthy (http://127.0.0.1:10248/healthz)." >&2
      exit 1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! retry 20 3 wget -qO- http://127.0.0.1:10248/healthz >/dev/null 2>&1; then
      echo "kubelet health endpoint is niet healthy (http://127.0.0.1:10248/healthz)." >&2
      exit 1
    fi
  else
    echo "Geen curl/wget beschikbaar voor kubelet health check." >&2
    exit 1
  fi
}

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

SCRIPT_ROOT="$(fetch_scripts_if_needed)"
SSH_SCRIPT="${SCRIPT_ROOT}/scripts/01_ssh/install_ssh.sh"
FIREWALL_SCRIPT="${SCRIPT_ROOT}/scripts/02_firewall/install_firewall.sh"
WIREGUARD_SCRIPT="${SCRIPT_ROOT}/scripts/03_wireguard/install_wireguard.sh"
KUBERNETES_SCRIPT="${SCRIPT_ROOT}/scripts/04_kubernetes/install_kubernetes.sh"
MASTER_SCRIPT="${SCRIPT_ROOT}/scripts/05_master/setup_master.sh"

INTERNAL_IP="$(ask_internal_ip)"
ROLE="$(ask_role)"
FIRST_MASTER="nee"
if [[ "$ROLE" == "master" ]]; then
  FIRST_MASTER="$(ask_first_master)"
fi
HOSTNAME_VALUE="$(ask_hostname)"

echo "Gekozen intern IP: ${INTERNAL_IP}"
echo "Gekozen role: ${ROLE}"
if [[ "$ROLE" == "master" ]]; then
  echo "Eerste master: ${FIRST_MASTER}"
fi
echo "Gekozen hostname: ${HOSTNAME_VALUE}"

echo "Hostname instellen..."
hostnamectl set-hostname "$HOSTNAME_VALUE"

echo "$ROLE" > /etc/linux_server_role
echo "Role opgeslagen in /etc/linux_server_role"

"$SSH_SCRIPT"
"$FIREWALL_SCRIPT"
check_network_ready
INTERNAL_IP="$INTERNAL_IP" "$WIREGUARD_SCRIPT"
check_wireguard_ready
"$KUBERNETES_SCRIPT"
check_kubelet_healthy

if [[ "$ROLE" == "master" && "$FIRST_MASTER" == "ja" ]]; then
  "$MASTER_SCRIPT"
fi

echo "Installatie afgerond."
