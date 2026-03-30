#!/usr/bin/env bash
set -euo pipefail

apt-get -y autoremove --purge
apt-get -y autoclean
