#!/usr/bin/env bash
set -euo pipefail

# Journald: bewaar maximaal 2 dagen (dit omvat ook kernel/firewall logs in journal).
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-retention.conf <<'CONF'
[Journal]
MaxRetentionSec=2day
CONF

# Logrotate defaults: dagelijks roteren, maximaal 2 archieven en hard max age 2 dagen.
if [[ -f /etc/logrotate.conf ]]; then
  sed -i -E 's/^\s*weekly\s*$/daily/' /etc/logrotate.conf || true

  if grep -qE '^\s*rotate\s+[0-9]+' /etc/logrotate.conf; then
    sed -i -E 's/^\s*rotate\s+[0-9]+\s*$/rotate 2/' /etc/logrotate.conf
  else
    printf '\nrotate 2\n' >> /etc/logrotate.conf
  fi

  if grep -qE '^\s*maxage\s+[0-9]+' /etc/logrotate.conf; then
    sed -i -E 's/^\s*maxage\s+[0-9]+\s*$/maxage 2/' /etc/logrotate.conf
  else
    printf 'maxage 2\n' >> /etc/logrotate.conf
  fi
fi

# Rsyslog-specifieke rotatie forceren naar max 2 dagen indien aanwezig.
if [[ -f /etc/logrotate.d/rsyslog ]]; then
  sed -i -E 's/^\s*weekly\s*$/daily/' /etc/logrotate.d/rsyslog || true

  if grep -qE '^\s*rotate\s+[0-9]+' /etc/logrotate.d/rsyslog; then
    sed -i -E 's/^\s*rotate\s+[0-9]+\s*$/    rotate 2/' /etc/logrotate.d/rsyslog
  else
    printf '    rotate 2\n' >> /etc/logrotate.d/rsyslog
  fi

  if grep -qE '^\s*maxage\s+[0-9]+' /etc/logrotate.d/rsyslog; then
    sed -i -E 's/^\s*maxage\s+[0-9]+\s*$/    maxage 2/' /etc/logrotate.d/rsyslog
  else
    printf '    maxage 2\n' >> /etc/logrotate.d/rsyslog
  fi
fi

systemctl restart systemd-journald
systemctl restart rsyslog 2>/dev/null || true
