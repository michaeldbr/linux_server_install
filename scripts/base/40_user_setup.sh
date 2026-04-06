#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/base/common.sh
source "${SCRIPT_DIR}/common.sh"

echo "[USER] Controleren of gebruiker '${MICHAEL_USER}' bestaat..."
if ! id -u "${MICHAEL_USER}" >/dev/null 2>&1; then
  echo "[USER] Gebruiker bestaat niet, aanmaken..."
  useradd -m -s /bin/bash "${MICHAEL_USER}"
else
  echo "[USER] Gebruiker bestaat al."
fi

current_uid="$(id -u "${MICHAEL_USER}")"
if [[ "${current_uid}" -eq 0 && "${MICHAEL_USER}" != "root" ]]; then
  echo "[USER] WAARSCHUWING: '${MICHAEL_USER}' heeft onveilige UID 0, herstellen..."
  next_uid="$(awk -F: 'BEGIN{max=999} $3>=1000 && $3<60000 {if($3>max) max=$3} END{print max+1}' /etc/passwd)"
  usermod -u "${next_uid}" "${MICHAEL_USER}"
fi

if ! getent group "${MICHAEL_USER}" >/dev/null 2>&1; then
  groupadd "${MICHAEL_USER}"
fi
usermod -g "${MICHAEL_USER}" -s /bin/bash "${MICHAEL_USER}"
usermod -aG sudo "${MICHAEL_USER}"

install -d -m 755 -o "${MICHAEL_USER}" -g "${MICHAEL_USER}" "/home/${MICHAEL_USER}"
passwd -l "${MICHAEL_USER}" || true

install -d -m 700 -o "${MICHAEL_USER}" -g "${MICHAEL_USER}" "/home/${MICHAEL_USER}/.ssh"
printf '%s\n' "${MICHAEL_KEY}" > "/home/${MICHAEL_USER}/.ssh/authorized_keys"
chown "${MICHAEL_USER}:${MICHAEL_USER}" "/home/${MICHAEL_USER}/.ssh/authorized_keys"
chmod 600 "/home/${MICHAEL_USER}/.ssh/authorized_keys"

echo "${MICHAEL_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${MICHAEL_USER}"
chmod 440 "/etc/sudoers.d/${MICHAEL_USER}"
visudo -cf "/etc/sudoers.d/${MICHAEL_USER}"

echo "[USER] Controleren of sudo zonder wachtwoord werkt..."
su - "${MICHAEL_USER}" -c "sudo -n true"
