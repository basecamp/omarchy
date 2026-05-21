#!/bin/bash

set -eEo pipefail

# Derive OMARCHY_PATH from the script location so install.sh works the same
# whether it's run from /usr/share/omarchy/install.sh (package mode) or
# $HOME/.local/share/omarchy/install.sh (git mode). An explicit OMARCHY_PATH
# in the caller env still wins.
_OMARCHY_INSTALLER_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export OMARCHY_PATH="${OMARCHY_PATH:-$_OMARCHY_INSTALLER_DIR}"
export OMARCHY_INSTALL="$OMARCHY_PATH/install"
export OMARCHY_INSTALL_LOG_FILE="/var/log/omarchy-install.log"
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
