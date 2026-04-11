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

if ! systemctl is-active --quiet apache2 && ! systemctl is-active --quiet httpd; then
  echo "Apache service is niet actief." >&2
  exit 1
fi

if ! iptables -C INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1; then
  echo "Firewall regel voor poort 80 ontbreekt." >&2
  exit 1
fi

if ! iptables -C INPUT -p tcp --dport 443 -j ACCEPT >/dev/null 2>&1; then
  echo "Firewall regel voor poort 443 ontbreekt." >&2
  exit 1
fi

if command -v a2query >/dev/null 2>&1; then
  for module in access_compat alias dir mime setenvif deflate filter headers ssl http2 rewrite; do
    if ! a2query -m "$module" | grep -q 'enabled'; then
      echo "Apache module niet enabled: $module" >&2
      exit 1
    fi
  done
fi

echo "Fase 2 frontend controle succesvol."
