# linux_server_install

## Gebruik

```bash
curl -fsSL https://raw.githubusercontent.com/michaeldbr/linux_server_install/main/install.sh | REPO_URL='https://github.com/michaeldbr/linux_server_install.git' BRANCH='main' bash
```

Met dit commando haal je `install.sh` op en voer je het direct uit op je server.

`install.sh` haalt automatisch de overige scripts op vanuit `REPO_URL` en `BRANCH` als ze lokaal nog niet bestaan, zodat dit out-of-the-box werkt met alleen de curl opdracht.

## Structuur

- `install.sh`: hoofdscript met de interactieve vragen (2x controle per invoer).
- `scripts/01_ssh/install_ssh.sh`: SSH installatie en hardening.
- `scripts/02_firewall/install_firewall.sh`: iptables regels + IPv6 firewall toepassen.
- `scripts/03_wireguard/install_wireguard.sh`: WireGuard installeren + `wg0.conf` en keys genereren.
- `scripts/04_kubernetes/install_kubernetes.sh`: containerd + `kubeadm`, `kubelet`, `kubectl` installatie en config.
- `scripts/05_master/install_haproxy.sh`: installeert/configureert HAProxy voor masters (`k8s-api.internal:6443`).
- `scripts/05_master/setup_master.sh`: role-specifieke master setup met `kubeadm init` en cluster post-init.
- `scripts/06_checks/check_etcd.sh`: basiscontrole voor control-plane endpoints en componentstatus.

## Wat doet het script?

- Vraagt 2x om het interne IP-adres en vergelijkt de antwoorden.
- Vraagt 2x om de role (`1` = master, `2` = worker) en vergelijkt de antwoorden.
- Bij role `master`: vraagt 2x of dit de eerste master is (`ja/nee`).
- Vraagt 2x om de hostname en vergelijkt de antwoorden.
- Maakt user `michael` aan (indien nog niet aanwezig).
- Configureert SSH key login voor `michael` met de opgegeven publieke sleutel.
- Zet SSH op poort `40111`.
- Zet root login via SSH uit.
- Installeert de gevraagde iptables regels.
- Staat FORWARD verkeer voor Kubernetes intern subnet `10.0.0.0/24` en pod CIDR `10.244.0.0/16` expliciet toe.
- Past ook IPv6 firewall regels toe (established eerst accept, daarna drop).
- Installeert WireGuard na de firewall-stap en maakt automatisch een werkende `wg0` configuratie aan (met `WG_ADDRESS=${INTERNAL_IP}/24`) zonder MASQUERADE NAT.
- Genereert server keys in `/etc/wireguard` en start `wg-quick@wg0`.
- Installeert containerd, zet de systemd cgroup driver aan, en installeert `kubeadm`, `kubelet` en `kubectl`.
- Controleert na firewall of netwerk/DNS klaar is voordat WireGuard/Kubernetes doorgaat.
- Controleert of WireGuard (`wg-quick@wg0` + interface `wg0`) echt actief is.
- Controleert na Kubernetes installatie of `kubelet` actief en healthy is.
- Controleert na master setup de API (`kubectl get nodes`) en voert etcd/control-plane basischeck uit.
- Logt na elke installatiestap expliciet `Stap ... afgerond ✔️` voor debugging.
- Voert op de eerste master `kubeadm init --control-plane-endpoint "10.0.0.1:6443" --upload-certs --pod-network-cidr=10.244.0.0/16` uit, zet `/home/michael/.kube/config`, en applyt Flannel CNI.
- Genereert op eerste master `/root/join.sh`; op extra masters (`FIRST_MASTER=nee`) wordt dit join script uitgevoerd voor control-plane join.
