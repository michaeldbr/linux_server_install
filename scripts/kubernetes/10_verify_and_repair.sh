#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[K8S-VERIFY] Start controle Kubernetes-laag..."

if ! command -v containerd >/dev/null 2>&1 || [[ ! -S /run/containerd/containerd.sock ]]; then
  bash "${SCRIPT_DIR}/01_install_containerd.sh"
fi

if ! grep -qE '^\s*SystemdCgroup\s*=\s*true' /etc/containerd/config.toml 2>/dev/null; then
  bash "${SCRIPT_DIR}/01_install_containerd.sh"
fi

if ! lsmod | grep -q '^overlay' || ! lsmod | grep -q '^br_netfilter'; then
  bash "${SCRIPT_DIR}/02_kernel_network_settings.sh"
fi

if [[ "$(sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null || echo 0)" != "1" ]] || [[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)" != "1" ]]; then
  bash "${SCRIPT_DIR}/02_kernel_network_settings.sh"
fi

if swapon --summary | tail -n +2 | grep -q .; then
  bash "${SCRIPT_DIR}/03_disable_swap.sh"
fi

if ! command -v kubeadm >/dev/null 2>&1 || ! command -v kubelet >/dev/null 2>&1 || ! command -v kubectl >/dev/null 2>&1; then
  bash "${SCRIPT_DIR}/04_install_kubernetes_packages.sh"
fi

if ! grep -q 'containerd.sock' /etc/default/kubelet 2>/dev/null; then
  bash "${SCRIPT_DIR}/05_configure_kubelet.sh"
fi

if [[ "$(systemctl is-enabled kubelet 2>/dev/null || true)" != "enabled" ]]; then
  systemctl enable kubelet
fi

echo "[K8S-VERIFY] Controle en herstel Kubernetes-laag afgerond."
