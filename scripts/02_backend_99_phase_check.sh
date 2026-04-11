#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f /etc/linux_server_role ]]; then
  echo "/etc/linux_server_role ontbreekt." >&2
  exit 1
fi

if [[ "$(cat /etc/linux_server_role)" != "backend" ]]; then
  echo "Role is niet backend." >&2
  exit 1
fi

echo "Fase 2 backend controle succesvol."
