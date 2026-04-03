# LINUX_Server_install

### Gebruik

```bash
curl -fsSL https://raw.githubusercontent.com/michaeldbr/linux_server_install/main/scripts/00_common/remote_bootstrap.sh | REPO_URL='https://github.com/michaeldbr/linux_server_install.git' BRANCH='main' bash


** STAP 1: Wireguard ip en public key ophalen huidige server:**

echo "IP: $(ip -4 addr show wg0 | grep inet | awk '{print $2}' | cut -d/ -f1) | PUBKEY: $(sudo cat /etc/wireguard/public.key)"

**STAP 2: toevoegen van een Wireguard Peer op een nieuwe server:**

sudo bash -c 'cat >> /etc/wireguard/wg0.conf

**VOORBEELD** CONFIG WIREGUARD: [Interface]
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


**STAP 3: daarna herladen:**

sudo wg-quick down wg0 && sudo wg-quick up wg0
