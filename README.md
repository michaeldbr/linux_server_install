# linux_server_install

## Gebruik

```bash
curl -fsSL https://raw.githubusercontent.com/michaeldbr/linux_server_install/main/install.sh | REPO_URL='https://github.com/michaeldbr/linux_server_install.git' BRANCH='main' bash
```

Met dit commando haal je `install.sh` op en voer je het direct uit op je server.

## Structuur

- `install.sh`: hoofdscript met de interactieve vragen (2x controle per invoer).
- `scripts/01_ssh/install_ssh.sh`: SSH installatie en hardening.
- `scripts/02_firewall/install_firewall.sh`: iptables regels + IPv6 uitschakelen.
- `scripts/03_wireguard/install_wireguard.sh`: WireGuard installeren.

## Wat doet het script?

- Vraagt 2x om het interne IP-adres en vergelijkt de antwoorden.
- Vraagt 2x om de role (`1` = master, `2` = worker) en vergelijkt de antwoorden.
- Vraagt 2x om de hostname en vergelijkt de antwoorden.
- Maakt user `michael` aan (indien nog niet aanwezig).
- Configureert SSH key login voor `michael` met de opgegeven publieke sleutel.
- Zet SSH op poort `40111`.
- Zet root login via SSH uit.
- Installeert de gevraagde iptables regels.
- Schakelt IPv6 uit via sysctl.
- Installeert WireGuard na de firewall-stap.
