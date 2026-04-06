#!/usr/bin/env bash
set -euo pipefail

echo "[K8S] crictl (optioneel) installeren indien beschikbaar..."
if apt-cache show cri-tools >/dev/null 2>&1; then
  apt-get -y install cri-tools
  echo "[K8S] crictl geïnstalleerd via cri-tools."
else
  echo "[K8S] cri-tools pakket niet beschikbaar in huidige repositories, stap overgeslagen."
fi
