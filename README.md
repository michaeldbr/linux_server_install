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
│   │   ├── 01_system_update.sh
│   │   ├── 02_set_time_and_timezone.sh
│   │   ├── 03_install_ssh_packages.sh
│   │   ├── 04_configure_michael_user.sh
│   │   ├── 05_harden_ssh.sh
│   │   ├── 06_install_firewall_packages.sh
│   │   ├── 07_configure_firewall.sh
│   │   ├── 08_install_wireguard.sh
│   │   ├── 09_configure_logging.sh
│   │   ├── 10_verify_and_repair.sh
│   │   ├── 11_cleanup.sh
│   │   ├── common.sh
│   │   └── remote_bootstrap.sh
│   ├── kubernetes/
│   │   ├── 01_install_containerd.sh
│   │   ├── 02_kernel_network_settings.sh
│   │   ├── 03_disable_swap.sh
│   │   ├── 04_install_kubernetes_packages.sh
│   │   ├── 05_configure_kubelet.sh
│   │   ├── 06_install_crictl.sh
│   │   └── 10_verify_and_repair.sh
│   ├── roles/
│   │   ├── first-master.sh
│   │   ├── master.sh
│   │   ├── worker.sh
│   │   └── traffic.sh
│   └── services/
├── templates/
└── wireguard/
    └── config.json
```

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
curl -fsSL https://raw.githubusercontent.com/michaeldbr/linux_server_install/main/scripts/base/remote_bootstrap.sh | REPO_URL='https://github.com/michaeldbr/linux_server_install.git' BRANCH='main' bash
```

Backward-compatible bootstrap pad blijft ook beschikbaar:

```bash
curl -fsSL https://raw.githubusercontent.com/michaeldbr/linux_server_install/main/scripts/00_common/remote_bootstrap.sh | REPO_URL='https://github.com/michaeldbr/linux_server_install.git' BRANCH='main' bash
```

### Logging

- In de basisinstallatie wordt `systemd-journald` geconfigureerd met `MaxRetentionSec=2day`.
- Logs worden daarmee maximaal 2 dagen bewaard.
