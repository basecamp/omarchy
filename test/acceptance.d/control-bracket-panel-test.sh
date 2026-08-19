#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

hide_panel() {
  omarchy-shell shell hide omarchy.audio >/dev/null 2>&1 || true
}

trap hide_panel EXIT

# Ctrl+[ is the terminal-style equivalent of Escape for keyboard-driven panels.
omarchy-shell notifications dismissAll >/dev/null
wait_until "notification popups close" 15 layer_absent "omarchy-notifications"
omarchy-shell shell summon omarchy.audio >/dev/null
wait_until "Ctrl+[ panel opens" 15 layer_present "omarchy-keyboard-panel"
wait_until "Ctrl+[ panel content is visible" 15 screen_contains "Audio"
screenshot "success-panel-control-bracket-open"
wtype -M ctrl -k bracketleft -m ctrl
wait_until "Ctrl+[ closes a panel" 15 layer_absent "omarchy-keyboard-panel"
screenshot "success-panel-control-bracket-closed"

trap - EXIT
