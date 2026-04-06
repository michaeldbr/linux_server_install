#!/usr/bin/env bash
set -euo pipefail

echo "[LOGGING] Configureren van systemd-journald retentie op maximaal 2 dagen..."

install -d -m 755 /etc/systemd/journald.conf.d

cat > /etc/systemd/journald.conf.d/99-retention.conf <<'CONF'
[Journal]
MaxRetentionSec=2day
CONF

systemctl restart systemd-journald

echo "[LOGGING] Loggingretentie ingesteld op maximaal 2 dagen."
