# LINUX_Server_install

## Installatiescript

Gebruik `install_server.sh` op een nieuwe Linux server. De installatie bestaat nu uit 3 lagen:

1. **Base** (altijd)
2. **Kubernetes** (altijd, voorbereiden node)
3. **Role** (selecteerbaar)

De basisconfiguratie (SSH, firewall, WireGuard, logging) blijft gelijk, maar er is nu een extra Kubernetes-laag tussen base en role.

### Nieuwe scriptstructuur

```text
repo/
├── install_server.sh
├── scripts/
│   ├── base/
│   │   ├── 00_input.sh
│   │   ├── 10_system_update.sh
│   │   ├── 20_timezone.sh
│   │   ├── 30_ssh_packages.sh
│   │   ├── 40_user_setup.sh
│   │   ├── 50_ssh_hardening.sh
│   │   ├── 60_firewall_packages.sh
│   │   ├── 70_wireguard.sh
│   │   ├── 80_firewall_rules.sh
│   │   ├── 90_logging.sh
│   │   ├── 95_verify_repair.sh
│   │   ├── 99_cleanup.sh
│   │   ├── common.sh
│   │   └── bootstrap.sh
│   ├── kubernetes/
│   │   ├── 10_containerd.sh
│   │   ├── 20_kernel_network.sh
│   │   ├── 30_swap.sh
│   │   ├── 40_kube_packages.sh
│   │   ├── 50_kubelet_config.sh
│   │   ├── 60_crictl.sh
│   │   └── 95_verify_repair.sh
│   ├── roles/
│   │   ├── master/
│   │   │   ├── apply.sh
│   │   │   └── firewall.sh
│   │   ├── worker/
│   │   │   ├── apply.sh
│   │   │   └── firewall.sh
│   │   └── traffic/
│   │       ├── apply.sh
│   │       └── firewall.sh
│   └── services/
├── templates/
└── wireguard/
    └── config.json
```

### Firewall-opbouw: basis + rol-specifiek

- `scripts/base/80_firewall_rules.sh` bevat alleen de algemene regels die voor elke server gelden.
- De base maakt een lege chain `INPUT_ROLE` aan.
- Per rol wordt daarna `scripts/roles/<rol>/firewall.sh` uitgevoerd om alleen rol-specifieke poorten toe te voegen.
- Zo blijven gedeelde regels centraal en staan uitzonderingen bij de juiste rol.

### Input tijdens installatie

`install_server.sh` vraagt interactief (via `/dev/tty`) en altijd met dubbele bevestiging:

1. Intern IP (`10.0.0.X`)
2. Rol (`master`, `worker`, `traffic`)
3. Hostname

Als de twee antwoorden per vraag niet gelijk zijn, wordt die specifieke vraag opnieuw gesteld.


### Fase-gebaseerde execution (check + retry + repair / controlled fail)

De installer draait nu per fase:

1. `BASE`
2. `KUBERNETES`
3. `ROLE`
4. `VERIFY`

Per fase gebeurt:
- uitvoering (`run`)
- directe controle (`check`)
- bij mislukking: herstel (`repair`) en opnieuw checken
- maximaal `MAX_PHASE_ATTEMPTS` pogingen (default: `2`)
- als de fase daarna nog faalt: **gecontroleerde stop** (`controlled fail`) met duidelijke foutmelding

Je kunt aantal pogingen aanpassen via bijvoorbeeld:

```bash
MAX_PHASE_ATTEMPTS=3 bash ./install_server.sh
```

### Kubernetes-laag (tussen base en role)

Doel: node voorbereiden zodat Kubernetes kan draaien.

- Runtime & tools:
  - containerd installeren + configureren
  - kubeadm installeren
  - kubelet installeren
  - kubectl installeren
- Containerd config:
  - `SystemdCgroup = true`
  - socket: `/run/containerd/containerd.sock`
- Kernel & network settings:
  - modules: `overlay`, `br_netfilter`
  - sysctl: `net.bridge.bridge-nf-call-iptables=1`, `net.ipv4.ip_forward=1`
- Swap uit:
  - `swapoff -a`
  - swap entries uit `/etc/fstab`
- Kubelet basisconfig:
  - runtime endpoint op containerd socket
  - service `enable`
- Debug tools:
  - `crictl` (optioneel, indien package beschikbaar)
- Rolgedrag:
  - De installer voert **geen** `kubeadm init` of `kubeadm join` automatisch uit
  - Gebruik rol `master` voor control-plane voorbereiding
  - `kubeadm init` en `kubeadm join` voer je handmatig uit na de installatie
  - gebruikt `CONTROL_PLANE_ENDPOINT` + `HAPROXY_BIND_PORT` als control-plane endpoint
  - gebruikt `POD_NETWORK_CIDR=10.244.0.0/16` als default (overschrijfbaar via env)
- Repositories/packages:
  - Kubernetes apt repo toevoegen
  - `kubelet`, `kubeadm`, `kubectl` installeren en op hold zetten

### Control-plane endpoint service (haproxy + keepalived, out-of-the-box voor masters)

Voor rol `master` wordt `scripts/services/install_control_plane_lb.sh` aangeroepen.
Dit script installeert en start standaard zowel `haproxy` als `keepalived`.

- Standaard endpoint: `CONTROL_PLANE_ENDPOINT=10.0.0.100`
- Standaard HAProxy bindpoort: `HAPROXY_BIND_PORT=7443`
- Keepalived defaults:
  - `KEEPALIVED_ENABLED=true`
  - `KEEPALIVED_ROUTER_ID=51`
  - `KEEPALIVED_AUTH_PASS=K8sHA001` (max 8 chars door keepalived PASS auth)
  - `KEEPALIVED_INTERFACE` wordt automatisch gedetecteerd (voorkeur `wg0`)
  - `KEEPALIVED_LOCAL_IP` default: `${WIREGUARD_SERVER_IP}`
  - `KEEPALIVED_STATE` en `KEEPALIVED_PRIORITY` worden automatisch bepaald:
    - node met eerste backend-IP => `MASTER`
    - overige nodes => `BACKUP`
    - priority volgt backend-volgorde: `150`, `140`, `130`, ...
- `CONTROL_PLANE_BACKENDS` default:
  - `master`: `10.0.0.1,10.0.0.2,10.0.0.3`
  - andere rollen: `${WIREGUARD_SERVER_IP}` (indien gezet)

Aanbevolen in productie: zet `CONTROL_PLANE_ENDPOINT` en `CONTROL_PLANE_BACKENDS` expliciet zodat ze exact bij je netwerk passen.

### Gebruik

```bash
curl -fsSL https://raw.githubusercontent.com/michaeldbr/linux_server_install/main/scripts/base/bootstrap.sh | REPO_URL='https://github.com/michaeldbr/linux_server_install.git' BRANCH='main' bash
```

Backward-compatible bootstrap pad blijft ook beschikbaar:

```bash
curl -fsSL https://raw.githubusercontent.com/michaeldbr/linux_server_install/main/scripts/00_common/remote_bootstrap.sh | REPO_URL='https://github.com/michaeldbr/linux_server_install.git' BRANCH='main' bash
```

### Logging

- In de basisinstallatie wordt `systemd-journald` geconfigureerd met `MaxRetentionSec=2day`.
- Logs worden daarmee maximaal 2 dagen bewaard.

### Servers handmatig koppelen met WireGuard (netwerk opzetten + testen)

Als je peers niet via automation wilt toevoegen, kun je twee (of meer) servers handmatig koppelen.
Onderstaand voorbeeld gaat uit van:

- Server A: `10.0.0.1`
- Server B: `10.0.0.2`
- Interface: `wg0`
- Poort: `51820/udp`

Je kunt de WireGuard-config openen en aanpassen met:

```bash
sudo nano /etc/wireguard/wg0.conf
```

1. **Controleer op beide servers of WireGuard draait en het lokale adres klopt**

```bash
sudo systemctl status wg-quick@wg0 --no-pager
ip -4 addr show wg0
```

2. **Maak (indien nodig) direct een keypair en zet de public key meteen in een peer-file**

Handig als je op een nieuwe server nog geen sleutels hebt en je meteen de juiste peer-regel wilt bewaren:

```bash
# Voorbeeld op Server B (peer file voor Server A)
sudo install -d -m 700 /etc/wireguard/peers
sudo bash -c '
  umask 077
  [[ -f /etc/wireguard/private.key ]] || wg genkey > /etc/wireguard/private.key
  wg pubkey < /etc/wireguard/private.key > /etc/wireguard/public.key
  printf "[Peer]\nPublicKey = %s\nAllowedIPs = 10.0.0.1/32\nPersistentKeepalive = 25\n" "$(cat /etc/wireguard/public.key)" > /etc/wireguard/peers/server-a.peer
'
```

> Vervang in het voorbeeld `AllowedIPs` en de bestandsnaam naar de gewenste peer.  
> Deze stap maakt private/public key en schrijft de public key direct weg in een peer-file die je later in `wg0.conf` kunt opnemen of met `wg set` kunt gebruiken.

3. **Haal op elke server de public key op**

```bash
sudo cat /etc/wireguard/public.key
```

4. **Voeg op Server A de peer van Server B toe**

> Vervang `<PUBKEY_SERVER_B>` met de echte public key van Server B.

```bash
sudo wg set wg0 \
  peer <PUBKEY_SERVER_B> \
  allowed-ips 10.0.0.2/32 \
  persistent-keepalive 25
```

5. **Voeg op Server B de peer van Server A toe (met endpoint)**

> Vervang `<PUBKEY_SERVER_A>` met de echte public key van Server A.  
> Vervang `<PUB_IP_OF_DNS_SERVER_A>` met het publieke IP of DNS van Server A.

```bash
sudo wg set wg0 \
  peer <PUBKEY_SERVER_A> \
  endpoint <PUB_IP_OF_DNS_SERVER_A>:51820 \
  allowed-ips 10.0.0.1/32 \
  persistent-keepalive 25
```

6. **Peer handmatig toevoegen in `wg0.conf` (persistent config-bestand)**

Als je peers liever direct in de WireGuard-config beheert, voeg dan een `[Peer]` blok toe in `/etc/wireguard/wg0.conf`:

```ini
[Peer]
PublicKey = <PUBKEY_SERVER_A>
AllowedIPs = 10.0.0.1/32
Endpoint = <PUB_IP_OF_DNS_SERVER_A>:51820
PersistentKeepalive = 25
```

7. **Eigen private/public key bewaren in `[Interface]` in `wg0.conf`**

`[Interface]` gebruikt `PrivateKey`. De public key kun je in hetzelfde blok als comment opslaan:

```ini
[Interface]
PrivateKey = <PRIVATE_KEY_VAN_DEZE_SERVER>
# PublicKey = <PUBLIC_KEY_VAN_DEZE_SERVER>
Address = 10.0.0.2/24
ListenPort = 51820
```

Sleutels genereren (indien nodig) en in bestanden wegschrijven:

```bash
sudo bash -c 'umask 077; [[ -f /etc/wireguard/private.key ]] || wg genkey > /etc/wireguard/private.key; wg pubkey < /etc/wireguard/private.key > /etc/wireguard/public.key'
```

8. **Herlaad WireGuard-config**

```bash
sudo systemctl restart wg-quick@wg0
```

### WireGuard voorbeeldconfig (copy/paste)

```ini
[Interface]
PrivateKey = wBigDtF46xhwMGe1Oy/IC7OTk3Kri1LMO73yl+pViEU=
Address = 10.0.0.1
ListenPort = 51820

[Peer]
PublicKey =
Endpoint = 217.160.188.152:51820
AllowedIPs = 10.0.0.2/32
PersistentKeepalive = 25

[Peer]
PublicKey =
Endpoint = :51820
AllowedIPs = 10.0.0.3/32
PersistentKeepalive = 25

[Peer]
PublicKey =
Endpoint = :51820
AllowedIPs = 10.0.0.4/32
PersistentKeepalive = 25

[Peer]
PublicKey =
Endpoint = :51820
AllowedIPs = 10.0.0.5/32
PersistentKeepalive = 25

[Peer]
PublicKey =
Endpoint = :51820
AllowedIPs = 10.0.0.6/32
PersistentKeepalive = 25

[Peer]
PublicKey =
Endpoint = :51820
AllowedIPs = 10.0.0.7/32
PersistentKeepalive = 25

[Peer]
PublicKey =
Endpoint = :51820
AllowedIPs = 10.0.0.8/32
PersistentKeepalive = 25

[Peer]
PublicKey =
Endpoint = :51820
AllowedIPs = 10.0.0.9/32
PersistentKeepalive = 25
```

9. **Test of de tunnel werkt**

```bash
# Op Server A:
ping -c 3 10.0.0.2

# Op Server B:
ping -c 3 10.0.0.1
```

10. **Controleer handshake en dataverkeer**

```bash
sudo wg show wg0
```

Je ziet dan o.a. `latest handshake` en oplopende `transfer` counters. Als die ontbreken:

- controleer of UDP `51820` open staat op de host en eventuele cloud firewall;
- controleer of `allowed-ips` exact de peer-IP(s) bevat;
- controleer endpoint/IP/DNS en of de tijd op beide servers correct is (NTP).

### Drie masters koppelen (master + master + master)

De rol `master` installeert automatisch `haproxy` én `keepalived`, schrijft direct werkende configuraties weg (`/etc/haproxy/haproxy.cfg` en `/etc/keepalived/keepalived.conf`) en start/enable't beide services meteen.
Daarnaast wordt het endpoint opgeslagen in `/etc/linux-server-install/control-plane-endpoint`:

- `master`: endpoint = `10.0.0.100` (tenzij je `CONTROL_PLANE_ENDPOINT` overschrijft)

- HAProxy backend defaults:
  - `master`: `10.0.0.1:6443` t/m `10.0.0.3:6443`
  - optioneel te overschrijven met `CONTROL_PLANE_BACKENDS` (comma-separated)

> ✅ **Out-of-the-box voor 3 masters**
>
> Installeer op **master1**, **master2** en **master3** met exact hetzelfde endpoint en dezelfde backend-lijst.
> Daarna hoef je alleen nog WireGuard peers te koppelen en `kubeadm join` uit te voeren.
> Voorbeeld:
>
> ```bash
> # eerste master
> CONTROL_PLANE_ENDPOINT=10.0.0.100 CONTROL_PLANE_BACKENDS=10.0.0.1,10.0.0.2,10.0.0.3 bash scripts/roles/master/apply.sh
>
> # tweede master
> CONTROL_PLANE_ENDPOINT=10.0.0.100 CONTROL_PLANE_BACKENDS=10.0.0.1,10.0.0.2,10.0.0.3 bash scripts/roles/master/apply.sh
>
> # derde master
> CONTROL_PLANE_ENDPOINT=10.0.0.100 CONTROL_PLANE_BACKENDS=10.0.0.1,10.0.0.2,10.0.0.3 bash scripts/roles/master/apply.sh
> ```
>
> Keepalived kiest automatisch MASTER/BACKUP en priority op basis van `CONTROL_PLANE_BACKENDS`:
> - positie 1: `MASTER` met priority `150`
> - positie 2: `BACKUP` met priority `140`
> - positie 3: `BACKUP` met priority `130`
>
> Let op de LB-poort: HAProxy bindt hier bewust op `7443` om poortconflict met lokale kube-apiserver (`6443`) op master nodes te vermijden.
> Gebruik daarom kubeadm/join tegen `<VIP>:7443`.

Voorbeeld van de gegenereerde HAProxy-config:

```conf
frontend k8s_api_frontend
    bind *:7443
    default_backend k8s_api_backend

backend k8s_api_backend
    option tcp-check
    default-server inter 2s fall 3 rise 2
    server master1 10.0.0.1:6443 check
    server master2 10.0.0.2:6443 check
    server master3 10.0.0.3:6443 check
```

Voorbeeld van de gegenereerde keepalived-config:

```conf
vrrp_instance VI_K8S_API {
    state MASTER/BACKUP (auto)
    interface wg0 (auto, indien aanwezig)
    virtual_router_id 51
    priority 150/140/130 (auto)
    unicast_src_ip <WIREGUARD_SERVER_IP>
    unicast_peer {
        <andere master IP>
    }
    virtual_ipaddress {
        10.0.0.100/32 dev wg0
    }
}
```

De install scripts bereiden nodes voor, maar starten cluster `init`/`join` niet automatisch.
Gebruik na installatie:

1. Op **eerste master**:

```bash
sudo kubeadm init --control-plane-endpoint "<VIP_OF_LB>:7443" --upload-certs --pod-network-cidr=10.244.0.0/16
```

2. Op **eerste master**, CNI toepassen (default flannel):

```bash
sudo CNI_PLUGIN=flannel bash scripts/kubernetes/70_cni.sh
```

3. Op **eerste master**, join info ophalen:

```bash
kubeadm token create --print-join-command
kubeadm init phase upload-certs --upload-certs
```

4. Op **tweede master**:

```bash
sudo kubeadm join <VIP_OF_LB>:7443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH> --control-plane --certificate-key <CERT_KEY>
```

5. Controleren op de eerste master:

```bash
kubectl get nodes -o wide
kubectl get pods -A
```
