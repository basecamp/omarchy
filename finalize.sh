#!/bin/bash
#
# The in-target portion of an Omarchy install: preflight checks, package-level
# setup, system configuration, login wiring, post-install steps. Run AFTER the
# orchestrator (offline mode) or install.sh (online mode) has ensured the
# omarchy runtime + omarchy-base.packages set is already installed.
#
# Called by:
#   - install.sh (online mode, after pacman -Syu)
#   - orchestrator/main.py (offline mode, via arch-chroot -u $USER)
#
# Anything that *must* happen as root pre-user lives in the orchestrator; this
# script runs as the install user.

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

source "$OMARCHY_INSTALL/preflight/all.sh"
source "$OMARCHY_INSTALL/packaging/all.sh"
source "$OMARCHY_INSTALL/config/all.sh"
source "$OMARCHY_INSTALL/login/all.sh"
source "$OMARCHY_INSTALL/post-install/all.sh"
