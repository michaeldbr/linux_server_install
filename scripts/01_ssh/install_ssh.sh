#!/usr/bin/env bash
set -euo pipefail

PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAmp04tIimmABx6bUEA29zvJ2IaeyWWAJFOWnN0YELT9 eddsa-key-20260401"
SSH_PORT="40111"

install_openssh_if_needed() {
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y openssh-server
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y openssh-server
  elif command -v yum >/dev/null 2>&1; then
    yum install -y openssh-server
  else
    echo "Geen ondersteunde package manager gevonden om openssh-server te installeren." >&2
    exit 1
  fi
}

set_sshd_option() {
  local key="$1"
  local value="$2"
  local file="/etc/ssh/sshd_config"

  if grep -Eq "^[#[:space:]]*${key}[[:space:]]+" "$file"; then
    sed -i -E "s|^[#[:space:]]*${key}[[:space:]]+.*|${key} ${value}|" "$file"
  else
    echo "${key} ${value}" >> "$file"
  fi
}

restart_ssh_service() {
  if systemctl list-unit-files | grep -q '^ssh\.service'; then
    systemctl enable --now ssh
    systemctl restart ssh
  elif systemctl list-unit-files | grep -q '^sshd\.service'; then
    systemctl enable --now sshd
    systemctl restart sshd
  else
    echo "Kon ssh service niet vinden (ssh/sshd). Controleer handmatig." >&2
    exit 1
  fi
}

if id -u michael >/dev/null 2>&1; then
  echo "User michael bestaat al."
else
  echo "User michael aanmaken..."
  useradd -m -s /bin/bash michael
fi

mkdir -p /home/michael/.ssh
chmod 700 /home/michael/.ssh
printf '%s\n' "$PUBLIC_KEY" > /home/michael/.ssh/authorized_keys
chmod 600 /home/michael/.ssh/authorized_keys
chown -R michael:michael /home/michael/.ssh

install_openssh_if_needed

set_sshd_option "Port" "$SSH_PORT"
set_sshd_option "PermitRootLogin" "no"
set_sshd_option "PasswordAuthentication" "no"
set_sshd_option "PubkeyAuthentication" "yes"

sshd -t
restart_ssh_service

echo "SSH configuratie gereed op poort ${SSH_PORT}."
