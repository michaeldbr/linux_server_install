#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
# shellcheck source=scripts/00_common/common.sh
source "${REPO_ROOT}/scripts/00_common/common.sh"

retry_script() {
  local script_path="$1"
  echo "[VERIFY] Herstel: ${script_path}"
  bash "${REPO_ROOT}/${script_path}"
}

# 1) Benodigde pakketten
missing_packages=()
for pkg in openssh-server sudo iptables iptables-persistent netfilter-persistent tzdata wireguard wireguard-tools; do
  if ! dpkg -s "${pkg}" >/dev/null 2>&1; then
    missing_packages+=("${pkg}")
  fi
done

if [[ ${#missing_packages[@]} -gt 0 ]]; then
  retry_script "scripts/02_ssh/03_install_ssh_packages.sh"
  retry_script "scripts/03_firewall/06_install_firewall_packages.sh"
  retry_script "scripts/04_wireguard/08_install_wireguard.sh"
  retry_script "scripts/01_system/02_set_time_and_timezone.sh"
fi

# 2) Tijdzone/NTP
if [[ "$(timedatectl show -p Timezone --value 2>/dev/null || true)" != "Europe/Amsterdam" ]]; then
  retry_script "scripts/01_system/02_set_time_and_timezone.sh"
fi

# 3) Logging-retentie (journald + logrotate)
if ! grep -qE '^\s*MaxRetentionSec=2day\b' /etc/systemd/journald.conf /etc/systemd/journald.conf.d/*.conf 2>/dev/null; then
  retry_script "scripts/01_system/03_configure_log_retention.sh"
fi

if [[ -f /etc/logrotate.conf ]] && (! grep -qE '^\s*daily\b' /etc/logrotate.conf || ! grep -qE '^\s*rotate\s+2\b' /etc/logrotate.conf || ! grep -qE '^\s*maxage\s+2\b' /etc/logrotate.conf); then
  retry_script "scripts/01_system/03_configure_log_retention.sh"
fi

if [[ -f /etc/logrotate.d/rsyslog ]] && (! grep -qE '^\s*daily\b' /etc/logrotate.d/rsyslog || ! grep -qE '^\s*rotate\s+2\b' /etc/logrotate.d/rsyslog || ! grep -qE '^\s*maxage\s+2\b' /etc/logrotate.d/rsyslog); then
  retry_script "scripts/01_system/03_configure_log_retention.sh"
fi

# 4) SSH configuratie
if ! grep -qE '^\s*PermitRootLogin\s+no\b' /etc/ssh/sshd_config || ! grep -qE "^\s*Port\s+${SSH_PORT}\b" /etc/ssh/sshd_config; then
  retry_script "scripts/02_ssh/05_harden_ssh.sh"
fi

# 5) User michael + key + sudoers
if ! id -u "${MICHAEL_USER}" >/dev/null 2>&1 || ! grep -Fq "${MICHAEL_KEY}" "/home/${MICHAEL_USER}/.ssh/authorized_keys" 2>/dev/null || [[ ! -f "/etc/sudoers.d/${MICHAEL_USER}" ]]; then
  retry_script "scripts/02_ssh/04_configure_michael_user.sh"
fi

if [[ "$(id -u "${MICHAEL_USER}")" -lt 1000 ]]; then
  retry_script "scripts/02_ssh/04_configure_michael_user.sh"
fi

if ! id -nG "${MICHAEL_USER}" | grep -qw sudo; then
  retry_script "scripts/02_ssh/04_configure_michael_user.sh"
fi

# 6) Firewall rules + persistence
if ! iptables -C INPUT -p tcp --dport "${SSH_PORT}" -j INPUT_SSH >/dev/null 2>&1; then
  retry_script "scripts/03_firewall/07_configure_firewall.sh"
fi

if ! iptables -C INPUT -p udp --dport "${WIREGUARD_PORT}" -j INPUT_WG >/dev/null 2>&1; then
  retry_script "scripts/03_firewall/07_configure_firewall.sh"
fi

if ! iptables -C INPUT -j INPUT_BASE >/dev/null 2>&1 || ! iptables -C INPUT -j LOG_DROP_DEFAULT >/dev/null 2>&1; then
  retry_script "scripts/03_firewall/07_configure_firewall.sh"
fi

if [[ "$(systemctl is-enabled netfilter-persistent 2>/dev/null || true)" != "enabled" ]]; then
  retry_script "scripts/03_firewall/07_configure_firewall.sh"
fi

if ! command -v wg >/dev/null 2>&1; then
  retry_script "scripts/04_wireguard/08_install_wireguard.sh"
fi

if [[ ! -f /etc/wireguard/wg0.conf ]]; then
  echo "[VERIFY] WAARSCHUWING: /etc/wireguard/wg0.conf ontbreekt. WireGuard is wel geïnstalleerd, maar nog niet geconfigureerd."
fi

if ! ip a show wg0 >/dev/null 2>&1; then
  echo "[VERIFY] WAARSCHUWING: wg0 interface niet actief, wg-quick@wg0 wordt gestart."
  systemctl enable wg-quick@wg0
  systemctl restart wg-quick@wg0
fi

if ! wg >/dev/null 2>&1; then
  echo "[VERIFY] WAARSCHUWING: 'wg' output niet beschikbaar, probeer WireGuard installatiestap opnieuw."
  retry_script "scripts/04_wireguard/08_install_wireguard.sh"
fi

if [[ -f /var/run/reboot-required ]]; then
  echo "[VERIFY] WAARSCHUWING: Reboot vereist om nieuwste kernel te laden."
fi

echo "[VERIFY] Controle en herstel afgerond."
