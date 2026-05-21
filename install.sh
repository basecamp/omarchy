#!/bin/bash

set -eEo pipefail

# Derive OMARCHY_PATH from the script location so install.sh works the same
# whether it's run from /usr/share/omarchy/install.sh (package mode) or
# $HOME/.local/share/omarchy/install.sh (git mode). An explicit OMARCHY_PATH
# in the caller env still wins.
_OMARCHY_INSTALLER_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
export OMARCHY_PATH="${OMARCHY_PATH:-$_OMARCHY_INSTALLER_DIR}"
export OMARCHY_INSTALL="$OMARCHY_PATH/install"
export OMARCHY_INSTALL_LOG_FILE="/var/log/omarchy-install.log"
export PATH="$OMARCHY_PATH/bin:$PATH"

source "$OMARCHY_INSTALL/helpers/mode.sh"
detect_install_mode
export_legacy_mode_flags

source "$OMARCHY_INSTALL/helpers/all.sh"

# The install scripts assume the full Omarchy default install set is present
# (preflight guards check for limine; config scripts call omarchy-* commands;
# user scripts call apps from omarchy-base.packages; etc.).
#
# omarchy itself only hard-depends on the bricking set (~18 packages). The
# rest of the default install set lives in install/omarchy-base.packages so
# users can remove non-essential apps without pacman blocking on a depend.
#
# Online: install omarchy + everything in omarchy-base.packages now.
# Offline: the ISO pacstraps the same set before user creation; just assert.
_omarchy_runtime_pkg="${OMARCHY_RUNTIME_PACKAGE:-omarchy}"
mapfile -t _omarchy_base_pkgs < <(grep -v '^#\|^$' "$OMARCHY_PATH/install/omarchy-base.packages")
if install_mode_is offline; then
  pacman -Q "$_omarchy_runtime_pkg" >/dev/null 2>&1 || {
    echo "Error: $_omarchy_runtime_pkg must be pacstrapped before omarchy-install runs in offline mode" >&2
    exit 1
  }
else
  sudo pacman -Syu --noconfirm --needed "$_omarchy_runtime_pkg" "${_omarchy_base_pkgs[@]}"
fi

source "$OMARCHY_INSTALL/preflight/all.sh"
source "$OMARCHY_INSTALL/packaging/all.sh"
source "$OMARCHY_INSTALL/config/all.sh"
source "$OMARCHY_INSTALL/login/all.sh"
source "$OMARCHY_INSTALL/post-install/all.sh"
