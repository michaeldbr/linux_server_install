#!/usr/bin/env bash
set -euo pipefail

CNI_PLUGIN="${CNI_PLUGIN:-flannel}"
CNI_FLANNEL_VERSION="${CNI_FLANNEL_VERSION:-v0.27.4}"
CNI_CALICO_VERSION="${CNI_CALICO_VERSION:-v3.28.2}"
KUBECONFIG_PATH="${KUBECONFIG:-/etc/kubernetes/admin.conf}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[CNI] kubectl niet gevonden, CNI stap overslaan."
  exit 0
fi

if [[ ! -f "${KUBECONFIG_PATH}" ]]; then
  echo "[CNI] ${KUBECONFIG_PATH} bestaat nog niet."
  echo "[CNI] Draai eerst kubeadm init op een master node en run dit script daarna opnieuw."
  exit 0
fi

export KUBECONFIG="${KUBECONFIG_PATH}"

if ! kubectl version --request-timeout=5s >/dev/null 2>&1; then
  echo "[CNI] API server nog niet bereikbaar, CNI stap overslaan."
  exit 0
fi

install_flannel() {
  if kubectl -n kube-system get daemonset kube-flannel-ds >/dev/null 2>&1; then
    echo "[CNI] Flannel lijkt al geïnstalleerd, stap overslaan."
    return 0
  fi

  echo "[CNI] Flannel installeren (${CNI_FLANNEL_VERSION})..."
  kubectl apply -f "https://github.com/flannel-io/flannel/releases/download/${CNI_FLANNEL_VERSION}/kube-flannel.yml"
}

install_calico() {
  if kubectl -n kube-system get daemonset calico-node >/dev/null 2>&1; then
    echo "[CNI] Calico lijkt al geïnstalleerd, stap overslaan."
    return 0
  fi

  echo "[CNI] Calico installeren (${CNI_CALICO_VERSION})..."
  kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CNI_CALICO_VERSION}/manifests/calico.yaml"
}

case "${CNI_PLUGIN}" in
  flannel) install_flannel ;;
  calico) install_calico ;;
  *)
    echo "[CNI] Onbekende CNI_PLUGIN='${CNI_PLUGIN}'. Gebruik 'flannel' of 'calico'." >&2
    exit 1
    ;;
esac

echo "[CNI] CNI stap afgerond."
