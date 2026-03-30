#!/usr/bin/env bash
set -euo pipefail

apt-get -y install openssh-server sudo
systemctl enable --now ssh || systemctl enable --now sshd
