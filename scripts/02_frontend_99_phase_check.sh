#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f /etc/linux_server_role ]]; then
  echo "/etc/linux_server_role ontbreekt." >&2
  exit 1
fi

if [[ "$(cat /etc/linux_server_role)" != "frontend" ]]; then
  echo "Role is niet frontend." >&2
  exit 1
fi

echo "Fase 2 frontend controle succesvol."
