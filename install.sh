#!/bin/bash
#
# Online install entry point. Run by the user on an existing Arch system to
# install / refresh Omarchy. Guards the host, ensures the omarchy runtime is
# up to date, then hands off to finalize.sh for the actual configure work.
#
# Offline installs (from the ISO) skip this script entirely: the Python
# orchestrator owns disk, base, bootloader, and package install before calling
# finalize.sh directly in the chroot.

set -eEo pipefail

_OMARCHY_INSTALLER_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
export OMARCHY_PATH="${OMARCHY_PATH:-$_OMARCHY_INSTALLER_DIR}"
export OMARCHY_INSTALL="${OMARCHY_INSTALL:-$OMARCHY_PATH/install}"
export OMARCHY_INSTALL_LOG_FILE="${OMARCHY_INSTALL_LOG_FILE:-/var/log/omarchy-install.log}"
export PATH="$OMARCHY_PATH/bin:$PATH"

source "$OMARCHY_INSTALL/helpers/mode.sh"
detect_install_mode
export_legacy_mode_flags

source "$OMARCHY_INSTALL/helpers/all.sh"

# Online-only setup: sanity-check the host, show the logo, start capturing
# the install log to /var/log. The orchestrator handles all of this itself
# in offline mode, so finalize.sh's caller environment looks the same in
# both modes by the time finalize.sh runs.
source "$OMARCHY_INSTALL/preflight/guard.sh"
source "$OMARCHY_INSTALL/preflight/begin.sh"
run_logged "$OMARCHY_INSTALL/preflight/show-env.sh"

# Install/update the omarchy runtime + the default install set.
_omarchy_runtime_pkg="${OMARCHY_RUNTIME_PACKAGE:-omarchy}"
mapfile -t _omarchy_base_pkgs < <(grep -v '^#\|^$' "$OMARCHY_PATH/install/omarchy-base.packages")
sudo pacman -Syu --noconfirm --needed "$_omarchy_runtime_pkg" "${_omarchy_base_pkgs[@]}"

# Root/system setup first; user-home setup remains in finalize.sh below.
sudo env \
  OMARCHY_INSTALL_MODE="${OMARCHY_INSTALL_MODE:-}" \
  OMARCHY_ONLINE_INSTALL="${OMARCHY_ONLINE_INSTALL:-}" \
  OMARCHY_CHROOT_INSTALL="${OMARCHY_CHROOT_INSTALL:-}" \
  OMARCHY_PATH="$OMARCHY_PATH" \
  OMARCHY_INSTALL="$OMARCHY_INSTALL" \
  OMARCHY_INSTALL_LOG_FILE="$OMARCHY_INSTALL_LOG_FILE" \
  OMARCHY_START_TIME="${OMARCHY_START_TIME:-}" \
  OMARCHY_START_EPOCH="${OMARCHY_START_EPOCH:-}" \
  OMARCHY_USER_NAME="${OMARCHY_USER_NAME:-}" \
  OMARCHY_USER_EMAIL="${OMARCHY_USER_EMAIL:-}" \
  OMARCHY_MIRROR="${OMARCHY_MIRROR:-}" \
  OMARCHY_INSTALL_USER="$USER" \
  bash "$OMARCHY_PATH/system-finalize.sh"

exec bash "$OMARCHY_PATH/finalize.sh"
