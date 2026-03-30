#!/usr/bin/env bash
set -euo pipefail

MICHAEL_USER="michael"
MICHAEL_KEY='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCaPPev24cN+xLf4cV8il4JhIyt8POmpUWk2QjLKHvXuGzu4HmWn0qprb57gki5mYDvwaY6XHGjIV+xauWnOaD3UhiV54xSRgdf4P3Kow5yOa2cDVCSsUqCxEaHYsr/5qCnMnhlSeDXEPFQA6ngQY9pzI2M8UuqPm5/NrVlVARKzmzkM6TVXRLJRHv9jikfohpv68nUeKS7UBBThmJQvoHWvPHc7aYIbaT0This6OlHKQtt7iTItWhALGPtnaDU+gFnkNAR0RpSFT+INUJ/MIpKFhd2T1bhsDZ1TTHq0Zqb+OKAD7+76Tm5WR9w0fCpQwJSWeqtqFKaxvm1A5EkgPEx rsa-key-20260330'

if [[ ${EUID} -ne 0 ]]; then
  echo "Dit script moet als root worden uitgevoerd (bijv. met sudo)." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "[1/5] Systeem pakketlijsten verversen..."
apt-get update

echo "[2/5] Volledige systeemupdate uitvoeren..."
apt-get -y full-upgrade

echo "[3/5] OpenSSH server installeren..."
apt-get -y install openssh-server sudo
systemctl enable --now ssh || systemctl enable --now sshd

echo "[4/5] Gebruiker '${MICHAEL_USER}' configureren..."
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

echo "[5/5] Opschonen van ongebruikte pakketten..."
apt-get -y autoremove --purge
apt-get -y autoclean

echo "Installatie en configuratie zijn voltooid."
