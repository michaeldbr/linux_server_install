# LINUX_Server_install

## Installatiescript

Gebruik `install_server.sh` op een nieuwe Linux server. De werking is opgesplitst in mappen per programma/app en scripts met doorlopende nummering.

### Scriptstructuur (volgorde van uitvoering)

- `scripts/00_common/common.sh` - gedeelde variabelen.
- `scripts/00_common/remote_bootstrap.sh` - bootstrap voor remote installatie via 1 SSH-commando (download/run/cleanup).
- `scripts/01_system/01_system_update.sh` - systeemupdate.
- `scripts/01_system/02_set_time_and_timezone.sh` - tijd/datum synchronisatie en timezone op `Europe/Amsterdam`.
- `scripts/02_ssh/03_install_ssh_packages.sh` - installatie SSH/sudo.
- `scripts/02_ssh/04_configure_michael_user.sh` - user `michael` + SSH key + sudoers.
- `scripts/02_ssh/05_harden_ssh.sh` - root login uit + SSH op poort `40111`.
- `scripts/03_firewall/06_install_firewall_packages.sh` - installatie firewall pakketten.
- `scripts/03_firewall/07_configure_firewall.sh` - chain `ip`, INPUT forwarding regel voor SSH poort `40111` (TCP), opent WireGuard UDP poort `51820`, boot-activatie en apply.
- `scripts/03_firewall/09_install_wireguard.sh` - installatie van WireGuard.
- `scripts/04_system/10_verify_and_repair.sh` - controleert of alles correct is geïnstalleerd/geconfigureerd en probeert mislukte onderdelen gericht opnieuw.
- `scripts/04_system/11_cleanup.sh` - cleanup.

### Gebruik

Branch naar keuze (plak direct in SSH):

```bash
curl -fsSL https://raw.githubusercontent.com/michaeldbr/linux_server_install/<jouw-branch>/scripts/00_common/remote_bootstrap.sh | REPO_URL='https://github.com/michaeldbr/linux_server_install.git' BRANCH='<jouw-branch>' bash
```

Main branch (standaard):

```bash
curl -fsSL https://raw.githubusercontent.com/michaeldbr/linux_server_install/main/scripts/00_common/remote_bootstrap.sh | REPO_URL='https://github.com/michaeldbr/linux_server_install.git' BRANCH='main' bash
```

Dit bootstrap-script verwijdert tijdelijke bestanden na afloop en verwijdert `git` weer als dat alleen voor de installatie is bijgeplaatst.

### Firewalllogica

- Chain `ip`:
  - `ACCEPT` als source `188.207.111.246`
  - `ACCEPT` als source `145.53.102.212`
  - anders `DROP`
- In `INPUT` wordt SSH verkeer op poort `40111` (TCP) doorgestuurd naar chain `ip`.
- In `INPUT` wordt WireGuard verkeer op poort `51820` (UDP) doorgestuurd naar chain `wireguard`.
- Chain `wireguard` bevat als eerste regel `DROP`.
- Na configuratie wordt netfilter-persistent op boot geactiveerd (`enable`) en de config direct toegepast (`save` + `reload`).

### WireGuard peer toevoegen tussen servers

**STAP 1: WireGuard IP en public key ophalen op huidige server:**

```bash
echo "IP: $(ip -4 addr show wg0 | grep inet | awk '{print $2}' | cut -d/ -f1) | PUBKEY: $(sudo cat /etc/wireguard/public.key)"
```

**STAP 2: toevoegen van een WireGuard peer op een nieuwe server:**

```bash
sudo bash -c 'cat >> /etc/wireguard/wg0.conf'
```

VOORBEELD CONFIG WIREGUARD:

```ini
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = PRIVKEY_SERVER1

[Peer]
PublicKey = PUBKEY_SERVER2
AllowedIPs = 10.0.0.2/32
Endpoint = EXTERN_IP_SERVER2:51820
PersistentKeepalive = 25

[Peer]
PublicKey = PUBKEY_SERVER3
AllowedIPs = 10.0.0.3/32
Endpoint = EXTERN_IP_SERVER3:51820
PersistentKeepalive = 25
```

**STAP 3: daarna herladen:**

```bash
sudo wg-quick down wg0 && sudo wg-quick up wg0
```


test
