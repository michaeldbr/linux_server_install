#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Dit script moet als root worden uitgevoerd." >&2
  exit 1
fi

REPO_URL="${REPO_URL:-https://github.com/michaeldbr/linux_server_install.git}"
BRANCH="${BRANCH:-main}"
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [[ -n "$SCRIPT_SOURCE" ]]; then
  BASE_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
else
  BASE_DIR="$(pwd)"
fi
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
  local ssh_script_local="${BASE_DIR}/scripts/01_01_ssh.sh"
  local cronjob_script_local="${BASE_DIR}/scripts/01_02_cronjob.sh"
  local firewall_script_local="${BASE_DIR}/scripts/01_03_firewall.sh"
  local wg_script_local="${BASE_DIR}/scripts/01_04_wireguard.sh"
  local phase1_check_script_local="${BASE_DIR}/scripts/01_99_phase_check.sh"
  local phase2_frontend_apache_script_local="${BASE_DIR}/scripts/02_frontend_01_apache.sh"
  local phase2_frontend_firewall_script_local="${BASE_DIR}/scripts/02_frontend_02_firewall.sh"
  local phase2_frontend_letsencrypt_script_local="${BASE_DIR}/scripts/02_frontend_03_letsencrypt.sh"
  local phase2_frontend_check_script_local="${BASE_DIR}/scripts/02_frontend_99_phase_check.sh"
  local phase2_backend_check_script_local="${BASE_DIR}/scripts/02_backend_99_phase_check.sh"

  if [[ -x "$ssh_script_local" && -x "$cronjob_script_local" && -x "$firewall_script_local" && -x "$wg_script_local" && -x "$phase1_check_script_local" && -x "$phase2_frontend_apache_script_local" && -x "$phase2_frontend_firewall_script_local" && -x "$phase2_frontend_letsencrypt_script_local" && -x "$phase2_frontend_check_script_local" && -x "$phase2_backend_check_script_local" ]]; then
    echo "$BASE_DIR"
    return 0
  fi

  echo "Lokale scripts niet gevonden. Repo wordt opgehaald vanuit: ${REPO_URL} (branch: ${BRANCH})" >&2
  install_git_if_needed

  TMP_REPO_DIR="$(mktemp -d)"
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TMP_REPO_DIR"

  if [[ ! -x "$TMP_REPO_DIR/scripts/01_01_ssh.sh" || ! -x "$TMP_REPO_DIR/scripts/01_02_cronjob.sh" || ! -x "$TMP_REPO_DIR/scripts/01_03_firewall.sh" || ! -x "$TMP_REPO_DIR/scripts/01_04_wireguard.sh" || ! -x "$TMP_REPO_DIR/scripts/01_99_phase_check.sh" || ! -x "$TMP_REPO_DIR/scripts/02_frontend_01_apache.sh" || ! -x "$TMP_REPO_DIR/scripts/02_frontend_02_firewall.sh" || ! -x "$TMP_REPO_DIR/scripts/02_frontend_03_letsencrypt.sh" || ! -x "$TMP_REPO_DIR/scripts/02_frontend_99_phase_check.sh" || ! -x "$TMP_REPO_DIR/scripts/02_backend_99_phase_check.sh" ]]; then
    echo "Vereiste scripts ontbreken in de opgehaalde repository." >&2
    exit 1
  fi

  echo "$TMP_REPO_DIR"
}


check_minimum_resources() {
  local min_cpu=2
  local min_mem_kb=$((2 * 1024 * 1024))
  local cpu_count mem_kb

  cpu_count="$(nproc)"
  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"

  if (( cpu_count < min_cpu )); then
    echo "Onvoldoende CPU cores: minimaal ${min_cpu} vereist, gevonden ${cpu_count}." >&2
    exit 1
  fi

  if (( mem_kb < min_mem_kb )); then
    echo "Onvoldoende RAM: minimaal 2GB vereist." >&2
    exit 1
  fi
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

check_ssh_ready() {
  if ! grep -Eq '^[#[:space:]]*Port[[:space:]]+40111$' /etc/ssh/sshd_config; then
    echo "SSH poort 40111 staat niet correct in /etc/ssh/sshd_config." >&2
    return 1
  fi

  if ! systemctl is-active --quiet ssh && ! systemctl is-active --quiet sshd; then
    echo "SSH service is niet actief." >&2
    return 1
  fi
}

check_firewall_ready() {
  if ! iptables -S INPUT | grep -q -- '-P INPUT DROP'; then
    echo "Firewall INPUT policy staat niet op DROP." >&2
    return 1
  fi

  if ! iptables -C INPUT -p tcp --dport 40111 -j ACCEPT >/dev/null 2>&1; then
    echo "Firewall regel voor SSH poort 40111 ontbreekt." >&2
    return 1
  fi

  if ! iptables -C INPUT -p udp --dport 51820 -j ACCEPT >/dev/null 2>&1; then
    echo "Firewall regel voor WireGuard poort 51820 ontbreekt." >&2
    return 1
  fi
}

check_cronjob_ready() {
  if ! command -v crontab >/dev/null 2>&1; then
    echo "crontab command ontbreekt." >&2
    return 1
  fi

  if ! systemctl is-active --quiet cron && ! systemctl is-active --quiet crond; then
    echo "Cron service is niet actief." >&2
    return 1
  fi
}

check_apache_ready() {
  if ! systemctl is-active --quiet apache2 && ! systemctl is-active --quiet httpd; then
    echo "Apache service is niet actief." >&2
    return 1
  fi
}

check_frontend_firewall_ready() {
  if ! iptables -C INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1; then
    echo "Firewall regel voor poort 80 ontbreekt." >&2
    return 1
  fi

  if ! iptables -C INPUT -p tcp --dport 443 -j ACCEPT >/dev/null 2>&1; then
    echo "Firewall regel voor poort 443 ontbreekt." >&2
    return 1
  fi
}

check_letsencrypt_ready() {
  local domain="${1:-}"
  if [[ -z "$domain" ]]; then
    echo "LETSENCRYPT_DOMAIN ontbreekt voor controle." >&2
    return 1
  fi

  if ! command -v certbot >/dev/null 2>&1; then
    echo "certbot is niet geïnstalleerd." >&2
    return 1
  fi

  if ! certbot certificates 2>/dev/null | grep -q "Domains: .*${domain}"; then
    echo "Geen Let's Encrypt certificaat gevonden voor domein ${domain}." >&2
    return 1
  fi

  if systemctl list-unit-files | grep -q '^certbot\\.timer'; then
    if ! systemctl is-enabled certbot.timer >/dev/null 2>&1; then
      echo "certbot.timer is niet enabled." >&2
      return 1
    fi
  fi
}

check_frontend_letsencrypt_ready() {
  check_letsencrypt_ready "${LETSENCRYPT_DOMAIN:-}"
}

run_script_with_retries() {
  local check_fn="$1"
  local step_label="$2"
  shift 2
  local attempts=3
  local i

  for ((i=1; i<=attempts; i++)); do
    echo "Uitvoeren ${step_label} (poging ${i}/${attempts})..."
    if ! "$@"; then
      echo "${step_label} script faalde op poging ${i}." >&2
      continue
    fi

    if "$check_fn"; then
      echo "${step_label} afgerond ✔️"
      return 0
    fi

    echo "${step_label} check faalde op poging ${i}." >&2
  done

  echo "${step_label} niet succesvol na ${attempts} pogingen. Installatie wordt gestopt." >&2
  exit 1
}

run_phase_check_with_retries() {
  local phase_check_script="$1"
  local phase_label="$2"
  local fix_role="${3:-}"
  local attempts=3
  local i

  for ((i=1; i<=attempts; i++)); do
    echo "Controle ${phase_label} (poging ${i}/${attempts})..."
    if "$phase_check_script"; then
      echo "${phase_label} controle afgerond ✔️"
      return 0
    fi

    if [[ -n "$fix_role" ]]; then
      echo "$fix_role" > /etc/linux_server_role
      echo "Herstelactie: role opnieuw gezet op ${fix_role}."
    fi
  done

  echo "${phase_label} controle faalt na ${attempts} pogingen. Installatie wordt gestopt." >&2
  exit 1
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
    echo "Kies de role:" >&2
    echo "1) frontend" >&2
    echo "2) backend" >&2
    role_choice="$(ask_twice_match 'Voer 1 of 2 in: ')"

    case "$role_choice" in
      1)
        printf 'frontend'
        return 0
        ;;
      2)
        printf 'backend'
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

ask_domain() {
  local domain
  while true; do
    domain="$(ask_twice_match \"Wat is de publieke domeinnaam voor Let's Encrypt (bijv. app.example.com)? \")"
    if [[ "$domain" =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]; then
      printf '%s' "$domain"
      return 0
    fi
    echo "Ongeldige domeinnaam. Probeer opnieuw."
  done
}

ask_email() {
  local email
  while true; do
    email="$(ask_twice_match \"Wat is het e-mailadres voor Let's Encrypt meldingen? \")"
    if [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
      printf '%s' "$email"
      return 0
    fi
    echo "Ongeldig e-mailadres. Probeer opnieuw."
  done
}

SCRIPT_ROOT="$(fetch_scripts_if_needed)"
SSH_SCRIPT="${SCRIPT_ROOT}/scripts/01_01_ssh.sh"
CRONJOB_SCRIPT="${SCRIPT_ROOT}/scripts/01_02_cronjob.sh"
FIREWALL_SCRIPT="${SCRIPT_ROOT}/scripts/01_03_firewall.sh"
WIREGUARD_SCRIPT="${SCRIPT_ROOT}/scripts/01_04_wireguard.sh"
PHASE1_CHECK_SCRIPT="${SCRIPT_ROOT}/scripts/01_99_phase_check.sh"
PHASE2_FRONTEND_APACHE_SCRIPT="${SCRIPT_ROOT}/scripts/02_frontend_01_apache.sh"
PHASE2_FRONTEND_FIREWALL_SCRIPT="${SCRIPT_ROOT}/scripts/02_frontend_02_firewall.sh"
PHASE2_FRONTEND_LETSENCRYPT_SCRIPT="${SCRIPT_ROOT}/scripts/02_frontend_03_letsencrypt.sh"
PHASE2_FRONTEND_CHECK_SCRIPT="${SCRIPT_ROOT}/scripts/02_frontend_99_phase_check.sh"
PHASE2_BACKEND_CHECK_SCRIPT="${SCRIPT_ROOT}/scripts/02_backend_99_phase_check.sh"

check_minimum_resources
echo "Stap resource-check afgerond ✔️"

INTERNAL_IP="$(ask_internal_ip)"
ROLE="$(ask_role)"
HOSTNAME_VALUE="$(ask_hostname)"
LETSENCRYPT_DOMAIN=""
LETSENCRYPT_EMAIL=""
if [[ "$ROLE" == "frontend" ]]; then
  LETSENCRYPT_DOMAIN="$(ask_domain)"
  LETSENCRYPT_EMAIL="$(ask_email)"
  export LETSENCRYPT_DOMAIN LETSENCRYPT_EMAIL
fi

echo "Gekozen intern IP: ${INTERNAL_IP}"
echo "Gekozen role: ${ROLE}"
if [[ "$ROLE" == "backend" ]]; then
  echo "Backend role geselecteerd."
fi
echo "Gekozen hostname: ${HOSTNAME_VALUE}"
if [[ "$ROLE" == "frontend" ]]; then
  echo "Let's Encrypt domein: ${LETSENCRYPT_DOMAIN}"
  echo "Let's Encrypt e-mail: ${LETSENCRYPT_EMAIL}"
fi

echo "Hostname instellen..."
hostnamectl set-hostname "$HOSTNAME_VALUE"

echo "$ROLE" > /etc/linux_server_role
echo "Role opgeslagen in /etc/linux_server_role"

run_script_with_retries check_ssh_ready "Stap fase 1.01 SSH" "$SSH_SCRIPT"
run_script_with_retries check_cronjob_ready "Stap fase 1.02 cronjob" "$CRONJOB_SCRIPT"

check_network_ready
echo "Stap netwerk-check afgerond ✔️"

run_script_with_retries check_firewall_ready "Stap fase 1.03 firewall" "$FIREWALL_SCRIPT"

run_script_with_retries check_wireguard_ready "Stap fase 1.04 WireGuard" env "INTERNAL_IP=${INTERNAL_IP}" "$WIREGUARD_SCRIPT"
echo "Controle onderlinge connectiviteit..."
ping -c 2 10.0.0.1 || true
ping -c 2 10.0.0.2 || true
ping -c 2 10.0.0.3 || true
run_phase_check_with_retries "$PHASE1_CHECK_SCRIPT" "Fase 1"

if [[ "$ROLE" == "frontend" ]]; then
  run_script_with_retries check_apache_ready "Stap fase 2.frontend.01 Apache" "$PHASE2_FRONTEND_APACHE_SCRIPT"
  run_script_with_retries check_frontend_firewall_ready "Stap fase 2.frontend.02 firewall" "$PHASE2_FRONTEND_FIREWALL_SCRIPT"
  run_script_with_retries check_frontend_letsencrypt_ready "Stap fase 2.frontend.03 Let's Encrypt" env "LETSENCRYPT_DOMAIN=${LETSENCRYPT_DOMAIN}" "LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}" "$PHASE2_FRONTEND_LETSENCRYPT_SCRIPT"
  run_phase_check_with_retries "$PHASE2_FRONTEND_CHECK_SCRIPT" "Fase 2 frontend" "frontend"
elif [[ "$ROLE" == "backend" ]]; then
  run_phase_check_with_retries "$PHASE2_BACKEND_CHECK_SCRIPT" "Fase 2 backend" "backend"
fi

echo "Installatie afgerond."
