#!/bin/bash
#
# The in-target portion of an Omarchy install. This is intentionally boring:
# the caller has already prepared the system; all this script does is run the
# target-side setup scripts. The ISO parent owns UI/error handling, while the
# online path re-establishes its tty-backed traps below.

export OMARCHY_INSTALL_LOG_FILE="${OMARCHY_INSTALL_LOG_FILE:-/var/log/omarchy-install.log}"

if [[ ${OMARCHY_INSTALL_DEBUG:-} == "1" ]]; then
  if [[ -n ${OMARCHY_CHROOT_FINALIZER:-} || ${OMARCHY_INSTALL_MODE:-} == "offline" ]]; then
    if { mkdir -p "$(dirname "$OMARCHY_INSTALL_LOG_FILE")" && touch "$OMARCHY_INSTALL_LOG_FILE"; } 2>/dev/null; then
      exec >>"$OMARCHY_INSTALL_LOG_FILE" 2>&1
    else
      echo "[finalize-debug] WARNING: cannot write $OMARCHY_INSTALL_LOG_FILE; tracing to inherited stderr" >&2
    fi
  fi
  export PS4='+ ${BASH_SOURCE[0]##*/}:${LINENO}:${FUNCNAME[0]:-main}: '
  echo "[finalize-debug] tracing enabled for $$ at $(date -Is)"
  set -x
fi

set -eEo pipefail

_OMARCHY_INSTALLER_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
export OMARCHY_PATH="${OMARCHY_PATH:-$_OMARCHY_INSTALLER_DIR}"
export OMARCHY_INSTALL="${OMARCHY_INSTALL:-$_OMARCHY_INSTALLER_DIR/install}"
export PATH="$_OMARCHY_INSTALLER_DIR/bin:$OMARCHY_PATH/bin:$PATH"

# Do not source helpers/all.sh here. That bundle unconditionally pulls in
# presentation and interactive error handling, both of which assume a
# controlling tty. The ISO runs this file through arch-chroot with
# stdout/stderr captured by the parent. Keep the offline bootstrap to the
# non-interactive primitives the scripts below use.
source "$OMARCHY_INSTALL/helpers/mode.sh"
detect_install_mode
export_legacy_mode_flags
source "$OMARCHY_INSTALL/helpers/chroot.sh"
source "$OMARCHY_INSTALL/helpers/logging.sh"

# Online installs still run finalize.sh directly after install.sh execs it, so
# re-establish the interactive UI/error traps only for that tty-backed path.
if install_mode_is online; then
  source "$OMARCHY_INSTALL/helpers/presentation.sh"
  source "$OMARCHY_INSTALL/helpers/errors.sh"
fi

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
