# Server_install_Kubernet_node

## Installatiescript

Gebruik `install_server.sh` op een nieuwe Linux server. De werking is opgesplitst in mappen per programma/app en scripts met doorlopende nummering.

### Scriptstructuur (volgorde van uitvoering)

- `scripts/00_common/common.sh` - gedeelde variabelen.
- `scripts/01_system/01_system_update.sh` - systeemupdate.
- `scripts/02_ssh/02_install_ssh_packages.sh` - installatie SSH/sudo.
- `scripts/02_ssh/03_configure_michael_user.sh` - user `michael` + SSH key + sudoers.
- `scripts/02_ssh/04_harden_ssh.sh` - root login uit + SSH op poort `40111`.
- `scripts/03_firewall/05_install_firewall_packages.sh` - installatie firewall pakketten.
- `scripts/03_firewall/06_configure_firewall.sh` - chain `ip`, INPUT forwarding regels voor poorten `40111` en `40112` (TCP/UDP), boot-activatie en apply.
- `scripts/04_system/07_cleanup.sh` - cleanup.

### Gebruik

```bash
sudo ./install_server.sh
```

### Firewalllogica

- Chain `ip`:
  - `ACCEPT` als source `188.207.111.246`
  - `ACCEPT` als source `145.53.102.212`
  - anders `DROP`
- In `INPUT` wordt verkeer voor poorten `40111` en `40112` (TCP/UDP) doorgestuurd naar chain `ip`.
- Na configuratie wordt netfilter-persistent op boot geactiveerd (`enable`) en de config direct toegepast (`save` + `reload`).
