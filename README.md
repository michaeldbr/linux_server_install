# Server_install_Kubernet_node

## Installatiescript

Gebruik `install_server.sh` op een nieuwe Linux server. De werking is opgesplitst in meerdere scripts voor overzicht en onderhoud.

### Scriptstructuur

- `install_server.sh` - hoofdscript/orchestratie.
- `scripts/common.sh` - gedeelde variabelen (gebruikersnaam, SSH-key, poort, allowed IP's).
- `scripts/10_system_update.sh` - systeemupdate.
- `scripts/20_install_ssh_and_firewall_packages.sh` - installatie OpenSSH/sudo/firewall pakketten.
- `scripts/30_configure_michael_user.sh` - user `michael` + SSH key + sudoers.
- `scripts/40_harden_ssh.sh` - root login uit + SSH op poort `40111`.
- `scripts/50_configure_firewall.sh` - chain `ip`, INPUT forwarding regels voor poorten `40111` en `40112` (TCP/UDP), netfilter-persistent op auto-start en directe apply.
- `scripts/60_cleanup.sh` - cleanup.

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
