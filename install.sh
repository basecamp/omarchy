#!/bin/bash
#
# Online install entry point. Run by the user on an existing system to install
# / refresh Omarchy. Ensures the omarchy runtime + omarchy-base.packages set
# is up to date, then hands off to finalize.sh for the actual configure work.
#
# Offline installs (from the ISO) skip this script entirely: the Python
# orchestrator handles partitioning, base install, package install, then calls
# finalize.sh directly inside the chroot.

set -eEo pipefail

_OMARCHY_INSTALLER_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
export OMARCHY_PATH="${OMARCHY_PATH:-$_OMARCHY_INSTALLER_DIR}"
export OMARCHY_INSTALL="$OMARCHY_PATH/install"
export OMARCHY_INSTALL_LOG_FILE="${OMARCHY_INSTALL_LOG_FILE:-/var/log/omarchy-install.log}"
export PATH="$OMARCHY_PATH/bin:$PATH"

source "$OMARCHY_INSTALL/helpers/mode.sh"
detect_install_mode
export_legacy_mode_flags

source "$OMARCHY_INSTALL/helpers/all.sh"

# The finalize scripts assume the omarchy runtime + the default install set are
# already on disk. In online mode we install them here; offline mode asserts
# (the orchestrator pacstraps them before calling finalize.sh directly).
_omarchy_runtime_pkg="${OMARCHY_RUNTIME_PACKAGE:-omarchy}"
mapfile -t _omarchy_base_pkgs < <(grep -v '^#\|^$' "$OMARCHY_PATH/install/omarchy-base.packages")
if install_mode_is offline; then
  pacman -Q "$_omarchy_runtime_pkg" >/dev/null 2>&1 || {
    echo "Error: $_omarchy_runtime_pkg must be installed before install.sh runs in offline mode" >&2
    exit 1
  }
else
  sudo pacman -Syu --noconfirm --needed "$_omarchy_runtime_pkg" "${_omarchy_base_pkgs[@]}"
fi

exec bash "$OMARCHY_PATH/finalize.sh"
