#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[K8S-VERIFY] Start controle Kubernetes-laag..."

if ! command -v containerd >/dev/null 2>&1 || [[ ! -S /run/containerd/containerd.sock ]]; then
  bash "${SCRIPT_DIR}/10_containerd.sh"
fi

if ! grep -qE '^\s*SystemdCgroup\s*=\s*true' /etc/containerd/config.toml 2>/dev/null; then
  bash "${SCRIPT_DIR}/10_containerd.sh"
fi

if ! lsmod | grep -q '^overlay' || ! lsmod | grep -q '^br_netfilter'; then
  bash "${SCRIPT_DIR}/20_kernel_network.sh"
fi

if [[ "$(sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null || echo 0)" != "1" ]] || [[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)" != "1" ]]; then
  bash "${SCRIPT_DIR}/20_kernel_network.sh"
fi

if swapon --summary | tail -n +2 | grep -q .; then
  bash "${SCRIPT_DIR}/30_swap.sh"
fi

if ! command -v kubeadm >/dev/null 2>&1 || ! command -v kubelet >/dev/null 2>&1 || ! command -v kubectl >/dev/null 2>&1; then
  bash "${SCRIPT_DIR}/40_kube_packages.sh"
fi

if ! grep -q 'containerd.sock' /etc/default/kubelet 2>/dev/null; then
  bash "${SCRIPT_DIR}/50_kubelet_config.sh"
fi

if [[ "$(systemctl is-enabled kubelet 2>/dev/null || true)" != "enabled" ]]; then
  systemctl enable kubelet
fi

echo "[K8S-VERIFY] Controle en herstel Kubernetes-laag afgerond."
