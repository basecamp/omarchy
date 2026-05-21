#!/bin/bash
#
# The in-target portion of an Omarchy install: package-level setup, system
# configuration, login wiring, post-install. Self-contained — works whether
# invoked by install.sh (online) or by the Python orchestrator (offline, via
# arch-chroot). The caller is responsible for system sanity checks (guards),
# UI styling, and log capture.

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

# Mark every shipped migration as "done" so future updates only run the new
# ones. Idempotent; safe to re-run.
mkdir -p ~/.local/state/omarchy/migrations
for _f in "$OMARCHY_PATH/migrations"/*.sh; do
  [[ -f $_f ]] && touch ~/.local/state/omarchy/migrations/"$(basename "$_f")"
done

source "$OMARCHY_INSTALL/packaging/all.sh"
source "$OMARCHY_INSTALL/config/all.sh"
source "$OMARCHY_INSTALL/login/all.sh"
source "$OMARCHY_INSTALL/post-install/all.sh"
