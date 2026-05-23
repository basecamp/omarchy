#!/usr/bin/env bash
# Ensure the offline/chroot finalizer can source helpers with no controlling tty.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

output="$({
  setsid -w bash -c '
    set -eEo pipefail
    export OMARCHY_INSTALL="$1/install"
    export OMARCHY_PATH="${OMARCHY_TEST_OMARCHY_PATH:-/usr/share/omarchy}"
    export OMARCHY_INSTALL_MODE=offline
    export OMARCHY_CHROOT_FINALIZER=1
    export HOME="$(mktemp -d)"
    export USER=ryan

    source "$OMARCHY_INSTALL/helpers/mode.sh"
    detect_install_mode
    export_legacy_mode_flags
    source "$OMARCHY_INSTALL/helpers/all.sh"
    echo helpers-loaded
  ' bash "$ROOT" </dev/null
} 2>&1)"

printf '%s\n' "$output"

if [[ $output != *helpers-loaded* ]]; then
  echo "expected helpers-loaded marker" >&2
  exit 1
fi

if [[ $output == *$'\033[?25h'* ]]; then
  echo "offline finalizer helper bootstrap leaked cursor escape" >&2
  exit 1
fi

echo "offline finalizer bootstrap test passed"
