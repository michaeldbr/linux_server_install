# Server_install_Kubernet_node

## Installatiescript

Gebruik `install_server.sh` op een nieuwe Linux server om automatisch:
- het hele systeem te updaten;
- OpenSSH server te installeren;
- gebruiker `michael` aan te maken met root-equivalente rechten (UID 0, GID 0), sudo rechten en SSH key-login;
- root login uit te schakelen;
- SSH te laten draaien op poort `40111`;
- Linux firewall regels te activeren met filtering op bron-IP voor poorten `40111` en `40112` (TCP/UDP).

### Gebruik

```bash
sudo ./install_server.sh
```

### Wat het script uitvoert

1. `apt-get update`
2. `apt-get full-upgrade -y`
3. `apt-get install -y openssh-server sudo iptables iptables-persistent netfilter-persistent`
4. `michael` gebruiker configureren (UID 0/GID 0, sudo NOPASSWD, SSH authorized_keys)
5. root account locken en `PermitRootLogin no` afdwingen in `sshd_config`
6. SSH `Port 40111` afdwingen in `sshd_config`
7. Firewall activeren met chain `ip`:
   - chain `ip`: `ACCEPT` voor bron `188.207.111.246`, `ACCEPT` voor bron `145.53.102.212`, daarna `DROP`
   - `INPUT` rules: verkeer naar poort `40111` en `40112` (TCP en UDP) gaat eerst naar chain `ip`
8. `apt-get autoremove --purge -y`
9. `apt-get autoclean -y`
