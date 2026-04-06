#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/base/common.sh
source "${SCRIPT_DIR}/scripts/base/common.sh"
# shellcheck source=scripts/base/00_input.sh
source "${SCRIPT_DIR}/scripts/base/00_input.sh"

MAX_PHASE_ATTEMPTS="${MAX_PHASE_ATTEMPTS:-2}"

if [[ ${EUID} -ne 0 ]]; then
  echo "Dit script moet als root worden uitgevoerd (bijv. met sudo)." >&2
  exit 1
fi

controlled_fail() {
  local phase="$1"
  echo "[FAIL] Fase '${phase}' kon niet succesvol afgerond worden na ${MAX_PHASE_ATTEMPTS} poging(en)." >&2
  echo "[FAIL] Installatie stopt gecontroleerd zonder onduidelijke tussenstatus." >&2
  exit 1
}

run_script() {
  local script_path="$1"
  bash "${SCRIPT_DIR}/${script_path}"
}

check_base_phase() {
  grep -qE '^\s*PermitRootLogin\s+no\b' /etc/ssh/sshd_config 2>/dev/null &&
  grep -qE "^\s*Port\s+${SSH_PORT}\b" /etc/ssh/sshd_config 2>/dev/null &&
  [[ -f /etc/wireguard/wg0.conf ]] &&
  iptables -C INPUT -j INPUT_BASE >/dev/null 2>&1 &&
  [[ -f /etc/systemd/journald.conf.d/99-retention.conf ]] &&
  grep -qE '^MaxRetentionSec=2day$' /etc/systemd/journald.conf.d/99-retention.conf 2>/dev/null
}

repair_base_phase() {
  run_script "scripts/base/10_verify_and_repair.sh"
}

run_base_phase() {
  run_script "scripts/base/01_system_update.sh"
  run_script "scripts/base/02_set_time_and_timezone.sh"
  run_script "scripts/base/03_install_ssh_packages.sh"
  run_script "scripts/base/04_configure_michael_user.sh"
  run_script "scripts/base/05_harden_ssh.sh"
  run_script "scripts/base/06_install_firewall_packages.sh"
  run_script "scripts/base/08_install_wireguard.sh"
  run_script "scripts/base/07_configure_firewall.sh"
  run_script "scripts/base/09_configure_logging.sh"
}

check_kubernetes_phase() {
  command -v containerd >/dev/null 2>&1 &&
  [[ -S /run/containerd/containerd.sock ]] &&
  grep -qE '^\s*SystemdCgroup\s*=\s*true' /etc/containerd/config.toml 2>/dev/null &&
  command -v kubeadm >/dev/null 2>&1 &&
  command -v kubelet >/dev/null 2>&1 &&
  command -v kubectl >/dev/null 2>&1 &&
  [[ "$(sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null || echo 0)" == "1" ]] &&
  [[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)" == "1" ]] &&
  ! swapon --summary | tail -n +2 | grep -q . &&
  grep -q 'containerd.sock' /etc/default/kubelet 2>/dev/null
}

repair_kubernetes_phase() {
  run_script "scripts/kubernetes/10_verify_and_repair.sh"
}

run_kubernetes_phase() {
  run_script "scripts/kubernetes/01_install_containerd.sh"
  run_script "scripts/kubernetes/02_kernel_network_settings.sh"
  run_script "scripts/kubernetes/03_disable_swap.sh"
  run_script "scripts/kubernetes/04_install_kubernetes_packages.sh"
  run_script "scripts/kubernetes/05_configure_kubelet.sh"
  run_script "scripts/kubernetes/06_install_crictl.sh"
}

run_role_phase() {
  run_script "scripts/roles/${SERVER_ROLE}.sh"
}

check_role_phase() {
  [[ "$(hostnamectl --static 2>/dev/null || hostname)" == "${TARGET_HOSTNAME}" ]] &&
  [[ -f /etc/server-role ]] &&
  [[ "$(cat /etc/server-role 2>/dev/null)" == "${SERVER_ROLE}" ]]
}

repair_role_phase() {
  run_role_phase
}

run_verify_phase() {
  run_script "scripts/base/10_verify_and_repair.sh"
}

check_verify_phase() {
  check_base_phase && check_kubernetes_phase && check_role_phase
}

repair_verify_phase() {
  run_verify_phase
}

execute_phase() {
  local phase_name="$1"
  local run_fn="$2"
  local check_fn="$3"
  local repair_fn="$4"

  local attempt
  for (( attempt=1; attempt<=MAX_PHASE_ATTEMPTS; attempt++ )); do
    echo "[PHASE:${phase_name}] Poging ${attempt}/${MAX_PHASE_ATTEMPTS}..."

    if "${run_fn}" && "${check_fn}"; then
      echo "[PHASE:${phase_name}] OK"
      return 0
    fi

    echo "[PHASE:${phase_name}] Check mislukt, repair uitvoeren..."
    "${repair_fn}" || true

    if "${check_fn}"; then
      echo "[PHASE:${phase_name}] OK na repair"
      return 0
    fi
  done

  controlled_fail "${phase_name}"
}

collect_install_input

echo "[PRE-FLIGHT] Interne IP ingesteld op ${WIREGUARD_SERVER_IP}."
echo "[PRE-FLIGHT] Gekozen rol: ${SERVER_ROLE}."
echo "[PRE-FLIGHT] Gekozen hostnaam: ${TARGET_HOSTNAME}."

echo "[INIT] Shell scripts uitvoerbaar maken..."
find "${SCRIPT_DIR}/scripts" -type f -name '*.sh' -exec chmod +x {} +

execute_phase "BASE" run_base_phase check_base_phase repair_base_phase
execute_phase "KUBERNETES" run_kubernetes_phase check_kubernetes_phase repair_kubernetes_phase
execute_phase "ROLE" run_role_phase check_role_phase repair_role_phase
execute_phase "VERIFY" run_verify_phase check_verify_phase repair_verify_phase

echo "[CLEANUP] Opschonen van ongebruikte pakketten..."
run_script "scripts/base/11_cleanup.sh"

echo "Klaar. SSH draait op poort ${SSH_PORT}. Tijdzone staat op Europe/Amsterdam."
echo "Installatie succesvol afgerond. Systeem wordt nu automatisch herstart..."
reboot
