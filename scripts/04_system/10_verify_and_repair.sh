#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
# shellcheck source=scripts/00_common/common.sh
source "${REPO_ROOT}/scripts/00_common/common.sh"

retry_script() {
  local script_path="$1"
  echo "[VERIFY] Herstel: ${script_path}"
  "${REPO_ROOT}/${script_path}"
}

# 1) Benodigde pakketten
missing_packages=()
for pkg in openssh-server sudo iptables iptables-persistent netfilter-persistent tzdata wireguard wireguard-tools webmin; do
  if ! dpkg -s "${pkg}" >/dev/null 2>&1; then
    missing_packages+=("${pkg}")
  fi
done

if [[ ${#missing_packages[@]} -gt 0 ]]; then
  retry_script "scripts/02_ssh/03_install_ssh_packages.sh"
  retry_script "scripts/03_firewall/06_install_firewall_packages.sh"
  retry_script "scripts/04_webmin/08_install_webmin.sh"
  retry_script "scripts/03_firewall/09_install_wireguard.sh"
  retry_script "scripts/01_system/02_set_time_and_timezone.sh"
fi

# 2) Tijdzone/NTP
if [[ "$(timedatectl show -p Timezone --value 2>/dev/null || true)" != "Europe/Amsterdam" ]]; then
  retry_script "scripts/01_system/02_set_time_and_timezone.sh"
fi

# 3) SSH configuratie
if ! grep -qE '^\s*PermitRootLogin\s+no\b' /etc/ssh/sshd_config || ! grep -qE "^\s*Port\s+${SSH_PORT}\b" /etc/ssh/sshd_config; then
  retry_script "scripts/02_ssh/05_harden_ssh.sh"
fi

# 4) User michael + key + sudoers
if ! id -u "${MICHAEL_USER}" >/dev/null 2>&1 || ! grep -Fq "${MICHAEL_KEY}" "/home/${MICHAEL_USER}/.ssh/authorized_keys" 2>/dev/null || [[ ! -f "/etc/sudoers.d/${MICHAEL_USER}" ]]; then
  retry_script "scripts/02_ssh/04_configure_michael_user.sh"
fi

# 5) Firewall rules + persistence
for proto in tcp udp; do
  for port in "${SSH_PORT}" "${WEBMIN_PORT}"; do
    if ! iptables -C INPUT -p "${proto}" --dport "${port}" -j ip >/dev/null 2>&1; then
      retry_script "scripts/03_firewall/07_configure_firewall.sh"
      break 2
    fi
  done
done

if ! iptables -C ip -s "${ALLOWED_IP_1}" -j ACCEPT >/dev/null 2>&1 || ! iptables -C ip -s "${ALLOWED_IP_2}" -j ACCEPT >/dev/null 2>&1 || ! iptables -C ip -j DROP >/dev/null 2>&1; then
  retry_script "scripts/03_firewall/07_configure_firewall.sh"
fi

if [[ "$(systemctl is-enabled netfilter-persistent 2>/dev/null || true)" != "enabled" ]]; then
  retry_script "scripts/03_firewall/07_configure_firewall.sh"
fi

# 6) Webmin user + poort
if ! grep -qE "^port=${WEBMIN_PORT}$" /etc/webmin/miniserv.conf 2>/dev/null; then
  retry_script "scripts/04_webmin/08_install_webmin.sh"
fi

if ! grep -qE "^${MICHAEL_USER}:" /etc/webmin/miniserv.users 2>/dev/null; then
  retry_script "scripts/04_webmin/08_install_webmin.sh"
fi

echo "[VERIFY] Controle en herstel afgerond."
