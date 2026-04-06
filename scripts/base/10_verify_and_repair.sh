#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
# shellcheck source=scripts/base/common.sh
source "${REPO_ROOT}/scripts/base/common.sh"

retry_script() {
  local script_path="$1"
  echo "[VERIFY] Herstel: ${script_path}"
  bash "${REPO_ROOT}/${script_path}"
}

echo "[VERIFY] Start controle..."

# 1) Benodigde pakketten
missing_packages=()
for pkg in openssh-server sudo iptables iptables-persistent netfilter-persistent tzdata wireguard wireguard-tools; do
  if ! dpkg -s "${pkg}" >/dev/null 2>&1; then
    missing_packages+=("${pkg}")
  fi
done

if [[ ${#missing_packages[@]} -gt 0 ]]; then
  echo "[VERIFY] Ontbrekende pakketten: ${missing_packages[*]}"
  retry_script "scripts/base/01_system_update.sh"
  retry_script "scripts/base/03_install_ssh_packages.sh"
  retry_script "scripts/base/06_install_firewall_packages.sh"
  retry_script "scripts/base/08_install_wireguard.sh"
fi

# 2) Tijdzone
if [[ "$(timedatectl show -p Timezone --value 2>/dev/null || true)" != "Europe/Amsterdam" ]]; then
  retry_script "scripts/base/02_set_time_and_timezone.sh"
fi

# 3) SSH configuratie
if ! grep -qE '^\s*PermitRootLogin\s+no\b' /etc/ssh/sshd_config; then
  retry_script "scripts/base/05_harden_ssh.sh"
fi

if ! grep -qE "^\s*Port\s+${SSH_PORT}\b" /etc/ssh/sshd_config; then
  retry_script "scripts/base/05_harden_ssh.sh"
fi

# 4) User michael + key + sudoers
if ! id -u "${MICHAEL_USER}" >/dev/null 2>&1; then
  retry_script "scripts/base/04_configure_michael_user.sh"
fi

if [[ ! -f "/home/${MICHAEL_USER}/.ssh/authorized_keys" ]]; then
  retry_script "scripts/base/04_configure_michael_user.sh"
fi

if ! grep -Fq "${MICHAEL_KEY}" "/home/${MICHAEL_USER}/.ssh/authorized_keys" 2>/dev/null; then
  retry_script "scripts/base/04_configure_michael_user.sh"
fi

if [[ ! -f "/etc/sudoers.d/${MICHAEL_USER}" ]]; then
  retry_script "scripts/base/04_configure_michael_user.sh"
fi

# 5) WireGuard
if ! command -v wg >/dev/null 2>&1; then
  retry_script "scripts/base/08_install_wireguard.sh"
fi

if [[ ! -f /etc/wireguard/wg0.conf ]]; then
  echo "[VERIFY] WAARSCHUWING: /etc/wireguard/wg0.conf ontbreekt."
  retry_script "scripts/base/08_install_wireguard.sh"
fi

if ! systemctl is-enabled wg-quick@wg0 >/dev/null 2>&1; then
  systemctl enable wg-quick@wg0
fi

if ! ip a show wg0 >/dev/null 2>&1; then
  echo "[VERIFY] wg0 interface niet actief, opnieuw starten..."
  systemctl restart wg-quick@wg0
fi

# 6) Firewall
if ! iptables -C INPUT -j INPUT_BASE >/dev/null 2>&1; then
  retry_script "scripts/base/07_configure_firewall.sh"
fi

if ! iptables -C INPUT_BASE -p tcp --dport "${SSH_PORT}" -j INPUT_SSH >/dev/null 2>&1; then
  retry_script "scripts/base/07_configure_firewall.sh"
fi

if ! iptables -C INPUT_BASE -p udp --dport "${WIREGUARD_PORT}" -j INPUT_WG >/dev/null 2>&1; then
  retry_script "scripts/base/07_configure_firewall.sh"
fi

if ! iptables -C INPUT_SSH -s "${ALLOWED_IP_1}" -j LOG_ACCEPT >/dev/null 2>&1; then
  retry_script "scripts/base/07_configure_firewall.sh"
fi

if ! iptables -C INPUT_SSH -s "${ALLOWED_IP_2}" -j LOG_ACCEPT >/dev/null 2>&1; then
  retry_script "scripts/base/07_configure_firewall.sh"
fi

if ! iptables -C INPUT_WG -j ACCEPT >/dev/null 2>&1; then
  retry_script "scripts/base/07_configure_firewall.sh"
fi

if [[ "$(systemctl is-enabled netfilter-persistent 2>/dev/null || true)" != "enabled" ]]; then
  systemctl enable netfilter-persistent
fi

# 7) Loggingretentie
if [[ ! -f /etc/systemd/journald.conf.d/99-retention.conf ]] || ! grep -qE '^MaxRetentionSec=2day$' /etc/systemd/journald.conf.d/99-retention.conf 2>/dev/null; then
  retry_script "scripts/base/09_configure_logging.sh"
fi

# 8) Kubernetes-laag
if ! command -v containerd >/dev/null 2>&1 || [[ ! -S /run/containerd/containerd.sock ]]; then
  retry_script "scripts/kubernetes/01_install_containerd.sh"
fi

if ! grep -qE '^\s*SystemdCgroup\s*=\s*true' /etc/containerd/config.toml 2>/dev/null; then
  retry_script "scripts/kubernetes/01_install_containerd.sh"
fi

if ! lsmod | grep -q '^overlay' || ! lsmod | grep -q '^br_netfilter'; then
  retry_script "scripts/kubernetes/02_kernel_network_settings.sh"
fi

if [[ "$(sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null || echo 0)" != "1" ]] || [[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)" != "1" ]]; then
  retry_script "scripts/kubernetes/02_kernel_network_settings.sh"
fi

if swapon --summary | tail -n +2 | grep -q .; then
  retry_script "scripts/kubernetes/03_disable_swap.sh"
fi

if ! command -v kubeadm >/dev/null 2>&1 || ! command -v kubelet >/dev/null 2>&1 || ! command -v kubectl >/dev/null 2>&1; then
  retry_script "scripts/kubernetes/04_install_kubernetes_packages.sh"
fi

if ! grep -q 'containerd.sock' /etc/default/kubelet 2>/dev/null; then
  retry_script "scripts/kubernetes/05_configure_kubelet.sh"
fi

if [[ "$(systemctl is-enabled kubelet 2>/dev/null || true)" != "enabled" ]]; then
  systemctl enable kubelet
fi

if [[ -f /var/run/reboot-required ]]; then
  echo "[VERIFY] WAARSCHUWING: Reboot vereist om nieuwste kernel te laden."
fi

echo "[VERIFY] Controle en herstel afgerond."
