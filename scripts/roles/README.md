# Roles

Elke rol heeft een eigen map met minimaal:

- `apply.sh`: rol-toepassing (hostname, role marker, etc.)
- `firewall.sh`: rol-specifieke firewallregels

De basis-firewall (`scripts/base/80_firewall_rules.sh`) zet alleen gedeelde regels en routeert extra regels via de `INPUT_ROLE` chain.
