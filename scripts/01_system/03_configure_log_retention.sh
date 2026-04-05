#!/usr/bin/env bash
set -euo pipefail

mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-retention.conf <<'CONF'
[Journal]
MaxRetentionSec=2day
CONF

systemctl restart systemd-journald
