#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/00_common/common.sh
source "${SCRIPT_DIR}/../00_common/common.sh"

passwd -l root || true

if grep -qE '^\s*PermitRootLogin\s+' /etc/ssh/sshd_config; then
  sed -i 's/^\s*PermitRootLogin\s\+.*/PermitRootLogin no/' /etc/ssh/sshd_config
else
  printf '\nPermitRootLogin no\n' >> /etc/ssh/sshd_config
fi

if grep -qE '^\s*Port\s+' /etc/ssh/sshd_config; then
  sed -i "s/^\s*Port\s\+.*/Port ${SSH_PORT}/" /etc/ssh/sshd_config
else
  printf '\nPort %s\n' "${SSH_PORT}" >> /etc/ssh/sshd_config
fi

systemctl restart ssh || systemctl restart sshd
