#!/usr/bin/env bash
set -euo pipefail

echo "[K8S] Kernel modules en netwerk sysctl instellen..."

cat > /etc/modules-load.d/k8s.conf <<'CONF'
overlay
br_netfilter
CONF

modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/99-kubernetes-cri.conf <<'CONF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
CONF

sysctl --system >/dev/null

echo "[K8S] Kernel/netwerk instellingen toegepast."
