#!/usr/bin/env bash
set -euo pipefail

MICHAEL_USER="michael"
MICHAEL_KEY='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCaPPev24cN+xLf4cV8il4JhIyt8POmpUWk2QjLKHvXuGzu4HmWn0qprb57gki5mYDvwaY6XHGjIV+xauWnOaD3UhiV54xSRgdf4P3Kow5yOa2cDVCSsUqCxEaHYsr/5qCnMnhlSeDXEPFQA6ngQY9pzI2M8UuqPm5/NrVlVARKzmzkM6TVXRLJRHv9jikfohpv68nUeKS7UBBThmJQvoHWvPHc7aYIbaT0This6OlHKQtt7iTItWhALGPtnaDU+gFnkNAR0RpSFT+INUJ/MIpKFhd2T1bhsDZ1TTHq0Zqb+OKAD7+76Tm5WR9w0fCpQwJSWeqtqFKaxvm1A5EkgPEx rsa-key-20260330'
SSH_PORT="40111"
ALLOWED_IP_1="188.207.111.246"
ALLOWED_IP_2="145.53.102.212"

if [[ ${EUID} -ne 0 ]]; then
  echo "Dit script moet als root worden uitgevoerd (bijv. met sudo)." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "[1/8] Systeem pakketlijsten verversen..."
apt-get update

echo "[2/8] Volledige systeemupdate uitvoeren..."
apt-get -y full-upgrade

echo "[3/8] OpenSSH server en firewall pakketten installeren..."
apt-get -y install openssh-server sudo iptables iptables-persistent netfilter-persistent
systemctl enable --now ssh || systemctl enable --now sshd

echo "[4/8] Gebruiker '${MICHAEL_USER}' configureren..."
if id -u "${MICHAEL_USER}" >/dev/null 2>&1; then
  usermod -o -u 0 -g 0 -s /bin/bash "${MICHAEL_USER}"
else
  useradd -m -o -u 0 -g 0 -s /bin/bash "${MICHAEL_USER}"
fi

# Zelfde groepen als root + sudo.
for group in $(id -nG root); do
  usermod -aG "${group}" "${MICHAEL_USER}" || true
done
usermod -aG sudo "${MICHAEL_USER}" || true

passwd -l "${MICHAEL_USER}" || true

install -d -m 700 -o "${MICHAEL_USER}" -g root "/home/${MICHAEL_USER}/.ssh"
printf '%s\n' "${MICHAEL_KEY}" > "/home/${MICHAEL_USER}/.ssh/authorized_keys"
chown "${MICHAEL_USER}":root "/home/${MICHAEL_USER}/.ssh/authorized_keys"
chmod 600 "/home/${MICHAEL_USER}/.ssh/authorized_keys"

echo "${MICHAEL_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${MICHAEL_USER}"
chmod 440 "/etc/sudoers.d/${MICHAEL_USER}"
visudo -cf "/etc/sudoers.d/${MICHAEL_USER}"

echo "[5/8] Root login uitschakelen..."
passwd -l root || true
if grep -qE '^\s*PermitRootLogin\s+' /etc/ssh/sshd_config; then
  sed -i 's/^\s*PermitRootLogin\s\+.*/PermitRootLogin no/' /etc/ssh/sshd_config
else
  printf '\nPermitRootLogin no\n' >> /etc/ssh/sshd_config
fi

echo "[6/8] SSH poort instellen op ${SSH_PORT}..."
if grep -qE '^\s*Port\s+' /etc/ssh/sshd_config; then
  sed -i "s/^\s*Port\s\+.*/Port ${SSH_PORT}/" /etc/ssh/sshd_config
else
  printf '\nPort %s\n' "${SSH_PORT}" >> /etc/ssh/sshd_config
fi
systemctl restart ssh || systemctl restart sshd

echo "[7/8] Firewall regels voor poorten 40111 en 40112 instellen..."
iptables -N ip 2>/dev/null || true
iptables -F ip
iptables -A ip -s "${ALLOWED_IP_1}" -j ACCEPT
iptables -A ip -s "${ALLOWED_IP_2}" -j ACCEPT
iptables -A ip -j DROP

for proto in tcp udp; do
  for port in 40111 40112; do
    while iptables -C INPUT -p "${proto}" --dport "${port}" -j ip 2>/dev/null; do
      iptables -D INPUT -p "${proto}" --dport "${port}" -j ip
    done
    iptables -A INPUT -p "${proto}" --dport "${port}" -j ip
  done
done

iptables-save > /etc/iptables/rules.v4
systemctl enable --now netfilter-persistent
systemctl restart netfilter-persistent

echo "[8/8] Opschonen van ongebruikte pakketten..."
apt-get -y autoremove --purge
apt-get -y autoclean

echo "Installatie en configuratie zijn voltooid. SSH draait op poort ${SSH_PORT}."
