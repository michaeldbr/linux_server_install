#!/usr/bin/env bash
set -euo pipefail

apt-get -y install openssh-server sudo iptables iptables-persistent netfilter-persistent
systemctl enable --now ssh || systemctl enable --now sshd
