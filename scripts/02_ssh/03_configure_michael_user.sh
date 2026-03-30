#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/00_common/common.sh
source "${SCRIPT_DIR}/../00_common/common.sh"

if id -u "${MICHAEL_USER}" >/dev/null 2>&1; then
  usermod -o -u 0 -g 0 -s /bin/bash "${MICHAEL_USER}"
else
  useradd -m -o -u 0 -g 0 -s /bin/bash "${MICHAEL_USER}"
fi

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
