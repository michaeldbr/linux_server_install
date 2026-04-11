# linux_server_install

## Gebruik

```bash
curl -fsSL https://raw.githubusercontent.com/michaeldbr/linux_server_install/main/install.sh | REPO_URL='https://github.com/michaeldbr/linux_server_install.git' BRANCH='main' bash
```

Met dit commando haal je `install.sh` op en voer je het direct uit op je server.

`install.sh` haalt automatisch de overige scripts op vanuit `REPO_URL` en `BRANCH` als ze lokaal nog niet bestaan, zodat dit out-of-the-box werkt met alleen de curl opdracht.

## Structuur

- `install.sh`: hoofdscript met de interactieve vragen (2x controle per invoer).
- `scripts/`: alle scripts staan direct in deze map (geen submappen).
- Fase 1 (server voorbereiden): `01_<applicatie>.sh`
  - `scripts/01_ssh.sh`: SSH installatie en hardening.
  - `scripts/01_firewall.sh`: iptables regels + IPv6 firewall toepassen.
  - `scripts/01_wireguard.sh`: WireGuard installeren + `wg0.conf` en keys genereren.
  - `scripts/01_kubernetes.sh`: containerd + `kubeadm`, `kubelet`, `kubectl` installatie en config.
  - `scripts/01_fluentbit.sh`: installeert Fluent Bit en forward logs naar centrale endpoint.
- Fase 2 (rollen): `02_<role>_<applicatie>.sh`
  - `scripts/02_master_haproxy.sh`: configureert bestaande HAProxy voor masters (`k8s-api.internal:7443`) zonder automatische installatie.
  - `scripts/02_master_setup.sh`: role-specifieke master setup met `kubeadm init` en cluster post-init.
  - `scripts/02_master_etcd_check.sh`: basiscontrole voor control-plane endpoints en componentstatus.

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
- Staat FORWARD verkeer voor Kubernetes intern subnet `10.0.0.0/24` en pod CIDR `10.244.0.0/16` expliciet toe, inclusief Kubernetes poorten `7443`, `6443`, `2379-2380`, `10250-10259` intern.
- Past ook IPv6 firewall regels toe (established eerst accept, daarna drop).
- Installeert WireGuard na de firewall-stap en maakt automatisch een werkende `wg0` configuratie aan (met `WG_ADDRESS=${INTERNAL_IP}/24`) met NAT die pod CIDR 10.244.0.0/16 uitsluit.
- Genereert server keys in `/etc/wireguard` en start `wg-quick@wg0`.
- Installeert/activeert tijdsync (`chrony` of `systemd-timesyncd`), zet timezone op `Europe/Amsterdam`, installeert containerd, zet de systemd cgroup driver aan, en installeert `kubeadm`, `kubelet` en `kubectl`.
- Controleert na firewall of netwerk/DNS klaar is voordat WireGuard/Kubernetes doorgaat.
- Controleert of WireGuard (`wg-quick@wg0` + interface `wg0`) echt actief is.
- Controleert na Kubernetes installatie of `kubelet` actief en healthy is.
- Controleert na master setup de API (`kubectl get nodes`) en voert etcd/control-plane basischeck uit.
- Installeert Fluent Bit voor log forwarding (incl. journald/iptables logs).
- Voert preflight resource-check uit (minimaal 2 CPU cores en 2GB RAM).
- Logt na elke installatiestap expliciet `Stap ... afgerond ✔️` voor debugging.
- Voert op de eerste master `kubeadm init` uit met `controlPlaneEndpoint: "k8s-api.internal:7443"`, zet `/home/michael/.kube/config`, en applyt Flannel CNI.
- Genereert op eerste master `/root/join.sh`; op extra masters (`FIRST_MASTER=nee`) wordt dit join script uitgevoerd voor control-plane join.
