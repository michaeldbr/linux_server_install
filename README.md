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
- Fase 2 (rollen): `02_<role>_<applicatie>.sh`
  - `scripts/02_backend_setup.sh`: role-specifieke backend setup (momenteel no-op placeholder).
  - `scripts/02_frontend_setup.sh`: role-specifieke frontend setup (momenteel no-op placeholder).

## Wat doet het script?

- Vraagt 2x om het interne IP-adres en vergelijkt de antwoorden.
- Vraagt 2x om de role (`1` = frontend, `2` = backend) en vergelijkt de antwoorden.
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
- Controleert na firewall of netwerk/DNS klaar is voordat WireGuard doorgaat.
- Controleert of WireGuard (`wg-quick@wg0` + interface `wg0`) echt actief is.
- Voert preflight resource-check uit (minimaal 2 CPU cores en 2GB RAM).
- Logt na elke installatiestap expliciet `Stap ... afgerond ✔️` voor debugging.
