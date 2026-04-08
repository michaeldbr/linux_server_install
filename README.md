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
│   │   ├── first-master/
│   │   │   ├── apply.sh
│   │   │   └── firewall.sh
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
2. Rol (`first-master`, `master`, `worker`, `traffic`)
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

Doel: node voorbereiden zodat Kubernetes kan draaien (zonder cluster init/join te starten).

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
- Repositories/packages:
  - Kubernetes apt repo toevoegen
  - `kubelet`, `kubeadm`, `kubectl` installeren en op hold zetten

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

### Twee masters koppelen (first-master + master)

De rol `first-master` en `master` installeren automatisch `keepalived` en `haproxy`.
Daarnaast wordt het endpoint opgeslagen in `/etc/linux-server-install/control-plane-endpoint`:

- `first-master`: endpoint = eigen server-IP (`WIREGUARD_SERVER_IP`)
- `master`: endpoint = `10.0.0.100` (tenzij je `CONTROL_PLANE_ENDPOINT` overschrijft)

De install scripts bereiden nodes voor, maar starten cluster init/join niet automatisch.
Gebruik na installatie:

1. Op **first-master**:

```bash
sudo kubeadm init --control-plane-endpoint "<VIP_OF_LB>:6443" --upload-certs --pod-network-cidr=10.244.0.0/16
```

2. Op **first-master**, CNI toepassen (default flannel):

```bash
sudo CNI_PLUGIN=flannel bash scripts/kubernetes/70_cni.sh
```

3. Op **first-master**, join info ophalen:

```bash
kubeadm token create --print-join-command
kubeadm init phase upload-certs --upload-certs
```

4. Op **tweede master**:

```bash
sudo kubeadm join <VIP_OF_LB>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH> --control-plane --certificate-key <CERT_KEY>
```

5. Controleren op first-master:

```bash
kubectl get nodes -o wide
kubectl get pods -A
```
