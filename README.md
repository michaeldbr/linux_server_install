# Server_install_Kubernet_node

## Installatiescript

Gebruik `install_server.sh` op een nieuwe Linux server om direct een volledige systeemupdate uit te voeren.

### Gebruik

```bash
sudo ./install_server.sh
```

Het script voert uit:
1. `apt-get update`
2. `apt-get full-upgrade -y`
3. `apt-get autoremove --purge -y`
4. `apt-get autoclean -y`
