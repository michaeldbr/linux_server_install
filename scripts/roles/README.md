# Roles

Elke rol heeft een eigen map met minimaal:

- `apply.sh`: rol-toepassing (hostname, role marker, etc.)
- `firewall.sh`: rol-specifieke firewallregels

Voor `master` bevat de rolmap aanvullend `kubeadm_init.sh`. Dit script voert
alleen `kubeadm init` uit wanneer het interne IP `10.0.0.1` is gekozen.

De basis-firewall (`scripts/base/80_firewall_rules.sh`) zet alleen gedeelde regels en routeert extra regels via de `INPUT_ROLE` chain.
