#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get -o Acquire::Retries=3 update

# Ubuntu mirrors can briefly become inconsistent (index points to package that is
# still syncing). Retry once after forcing a fresh package index.
if ! apt-get -o Acquire::Retries=3 -y full-upgrade; then
  echo "Apt upgrade failed, refreshing package lists and retrying..."
  apt-get clean
  rm -rf /var/lib/apt/lists/*
  apt-get -o Acquire::Retries=3 update
  apt-get -o Acquire::Retries=3 -y --fix-missing full-upgrade
fi
