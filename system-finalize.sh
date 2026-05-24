#!/bin/bash
#
# System-level Omarchy install work. This intentionally runs as root inside
# the target system. User-home setup stays in finalize.sh.

export OMARCHY_INSTALL_LOG_FILE="${OMARCHY_INSTALL_LOG_FILE:-/var/log/omarchy-install.log}"

set -eEo pipefail

_OMARCHY_INSTALLER_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
export OMARCHY_PATH="${OMARCHY_PATH:-$_OMARCHY_INSTALLER_DIR}"
export OMARCHY_INSTALL="${OMARCHY_INSTALL:-$_OMARCHY_INSTALLER_DIR/install}"
export PATH="${OMARCHY_PATH}/bin:$_OMARCHY_INSTALLER_DIR/bin:$PATH"

source "$OMARCHY_INSTALL/helpers/mode.sh"
detect_install_mode
export_legacy_mode_flags
source "$OMARCHY_INSTALL/helpers/chroot.sh"
source "$OMARCHY_INSTALL/helpers/logging.sh"

if (( EUID != 0 )); then
  echo "Error: system-finalize.sh must run as root" >&2
  exit 1
fi

if [[ -z ${OMARCHY_INSTALL_USER:-} || ${OMARCHY_INSTALL_USER:-} == "root" ]]; then
  echo "Error: system-finalize.sh requires OMARCHY_INSTALL_USER to name the target non-root user" >&2
  exit 1
fi

if ! getent passwd "$OMARCHY_INSTALL_USER" >/dev/null; then
  echo "Error: OMARCHY_INSTALL_USER=$OMARCHY_INSTALL_USER does not exist" >&2
  exit 1
fi

source "$OMARCHY_INSTALL/system/all.sh"
