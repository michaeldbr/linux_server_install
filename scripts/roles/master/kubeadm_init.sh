#!/usr/bin/env bash
set -euo pipefail

ROLE_NAME="master"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONTROL_PLANE_ENDPOINT="${CONTROL_PLANE_ENDPOINT:-k8s-api.local}"
HAPROXY_BIND_PORT="${HAPROXY_BIND_PORT:-7443}"
POD_NETWORK_CIDR="${POD_NETWORK_CIDR:-10.244.0.0/16}"
KUBEADM_JOIN_PATH="${KUBEADM_JOIN_PATH:-/root/kubeadm_join.sh}"

if [[ "${WIREGUARD_SERVER_IP:-}" != "10.0.0.1" ]]; then
  echo "[ROLE:${ROLE_NAME}] kubeadm init niet nodig: intern IP is ${WIREGUARD_SERVER_IP:-onbekend}."
  exit 0
fi

if [[ -f /etc/kubernetes/admin.conf ]]; then
  echo "[ROLE:${ROLE_NAME}] kubeadm init al uitgevoerd (/etc/kubernetes/admin.conf bestaat)."
  exit 0
fi

if [[ ! -S /run/containerd/containerd.sock ]]; then
  echo "[ROLE:${ROLE_NAME}] FOUT: containerd socket ontbreekt, kubeadm init kan niet starten." >&2
  exit 1
fi

echo "[ROLE:${ROLE_NAME}] kubeadm init starten op eerste master (${WIREGUARD_SERVER_IP})..."
kubeadm init \
  --control-plane-endpoint "${CONTROL_PLANE_ENDPOINT}:${HAPROXY_BIND_PORT}" \
  --upload-certs \
  --pod-network-cidr="${POD_NETWORK_CIDR}" \
  --apiserver-advertise-address="${WIREGUARD_SERVER_IP}"

worker_join_command="$(kubeadm token create --print-join-command)"
certificate_key="$(kubeadm init phase upload-certs --upload-certs | tail -n 1 | xargs)"

cat > "${KUBEADM_JOIN_PATH}" <<CFG
#!/usr/bin/env bash
set -euo pipefail

# Worker node join
${worker_join_command}

# Extra control-plane node join
${worker_join_command} --control-plane --certificate-key ${certificate_key}
CFG
chmod 0700 "${KUBEADM_JOIN_PATH}"

target_home="${HOME:-/root}"
install -d -m 0700 "${target_home}/.kube"
cp -f /etc/kubernetes/admin.conf "${target_home}/.kube/config"
chown "$(id -u):$(id -g)" "${target_home}/.kube/config"
chmod 0600 "${target_home}/.kube/config"

echo "[ROLE:${ROLE_NAME}] kubeadm init succesvol afgerond."
