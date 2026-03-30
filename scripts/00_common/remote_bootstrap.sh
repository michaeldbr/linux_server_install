#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Dit script moet als root worden uitgevoerd." >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "Alleen Debian/Ubuntu (apt-get) wordt ondersteund door dit bootstrap-script." >&2
  exit 1
fi

REPO_URL="${REPO_URL:-https://github.com/michaeldbr/linux_server_install.git}"
BRANCH="${BRANCH:-main}"

cleanup_dir=""
installed_git=0

cleanup() {
  if [[ -n "${cleanup_dir}" && -d "${cleanup_dir}" ]]; then
    rm -rf "${cleanup_dir}"
  fi

  if [[ ${installed_git} -eq 1 ]]; then
    echo "Git was tijdelijk geïnstalleerd en wordt nu verwijderd..."
    DEBIAN_FRONTEND=noninteractive apt-get purge -y git >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y >/dev/null
  fi
}
trap cleanup EXIT

if ! command -v git >/dev/null 2>&1; then
  echo "Git ontbreekt, tijdelijk installeren..."
  DEBIAN_FRONTEND=noninteractive apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y git ca-certificates
  installed_git=1
fi

cleanup_dir="$(mktemp -d /tmp/server-install.XXXXXX)"
repo_dir="${cleanup_dir}/repo"

echo "Repository klonen (${BRANCH})..."
git clone --depth 1 --branch "${BRANCH}" "${REPO_URL}" "${repo_dir}"

echo "Installatie uitvoeren..."
cd "${repo_dir}"
./install_server.sh

echo "Klaar. Tijdelijke bestanden zijn opgeruimd."
