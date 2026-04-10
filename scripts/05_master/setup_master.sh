#!/usr/bin/env bash
sed -i '/k8s-api.internal/d' /etc/hosts
echo "127.0.0.1 k8s-api.internal" >> /etc/hosts

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HAPROXY_SCRIPT="${BASE_DIR}/install_haproxy.sh"
KUBEADM_CONFIG_FILE="/etc/kubernetes/kubeadm-config.yaml"

if [[ ! -x "$HAPROXY_SCRIPT" ]]; then
  echo "HAProxy script ontbreekt of is niet uitvoerbaar: $HAPROXY_SCRIPT" >&2
  exit 1
fi

write_kubeadm_config() {
  mkdir -p /etc/kubernetes
  cat > "$KUBEADM_CONFIG_FILE" <<'YAML'
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
controlPlaneEndpoint: "k8s-api.internal:7443"
networking:
  podSubnet: "10.244.0.0/16"
YAML
}

create_join_script() {
  local join_cmd cert_key

  join_cmd="$(kubeadm token create --print-join-command)"
  cert_key="$(kubeadm init phase upload-certs --upload-certs | tail -n 1)"

  cat > /root/join.sh <<JOIN
#!/usr/bin/env bash
set -euo pipefail
${join_cmd} --control-plane --certificate-key ${cert_key}
JOIN

  chmod 700 /root/join.sh
  echo "Join script aangemaakt: /root/join.sh"
}

run_kubeadm_init_if_first_master() {
  if [[ "${FIRST_MASTER:-nee}" != "ja" ]]; then
    echo "Dit is geen eerste master; kubeadm init wordt overgeslagen."
    return 0
  fi

  if [[ -f /etc/kubernetes/admin.conf ]]; then
    echo "Kubernetes master lijkt al geinitialiseerd (/etc/kubernetes/admin.conf bestaat al)."
    return 0
  fi

  write_kubeadm_config

  echo "Start kubeadm init met control-plane endpoint k8s-api.internal:7443..."
  kubeadm init --config "$KUBEADM_CONFIG_FILE" --upload-certs

  create_join_script

  echo "kubeadm init voltooid."
}

check_api_server() {
  if [[ ! -f /etc/kubernetes/admin.conf ]]; then
    return 0
  fi

  echo "Controle API server..."

  if ! su - michael -c "kubectl get nodes" >/dev/null 2>&1; then
    echo "API server niet bereikbaar!" >&2
    exit 1
  fi
}

post_init_setup() {
  if [[ ! -f /etc/kubernetes/admin.conf ]]; then
    return 0
  fi

  echo "Kubeconfig instellen voor user michael..."
  mkdir -p /home/michael/.kube
  cp /etc/kubernetes/admin.conf /home/michael/.kube/config
  chown -R michael:michael /home/michael/.kube

  if [[ "${FIRST_MASTER:-nee}" == "ja" ]]; then
    echo "CNI (Flannel) installeren..."
    su - michael -c "kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml"

    echo "Wachten tot nodes Ready zijn..."
    su - michael -c "kubectl wait --for=condition=Ready node --all --timeout=120s"
  fi
}

"$HAPROXY_SCRIPT"
run_kubeadm_init_if_first_master
post_init_setup
check_api_server

echo "Master setup voltooid: HAProxy + (optioneel) kubeadm init + kubeconfig/Flannel + API check."
