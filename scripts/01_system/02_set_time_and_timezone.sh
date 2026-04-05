#!/usr/bin/env bash
set -euo pipefail

apt-get -y install tzdata

# Tijd synchronisatie aanzetten en timezone op Europe/Amsterdam zetten.
timedatectl set-ntp true
timedatectl set-timezone Europe/Amsterdam

# Toon huidige status voor logging.
timedatectl status
