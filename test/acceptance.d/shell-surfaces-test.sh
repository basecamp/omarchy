#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

open_and_close() {
  local name="$1" plugin="$2" namespace="$3" payload="${4:-}"

  if [[ -n $payload ]]; then
    omarchy-shell shell summon "$plugin" "$payload" >/dev/null
  else
    omarchy-shell shell summon "$plugin" >/dev/null
  fi

  wait_until "$name opens" 15 layer_present "$namespace"
  sleep 1
  screenshot "$name-open"

  omarchy-shell shell hide "$plugin" >/dev/null
  wait_until "$name closes" 15 layer_absent "$namespace"
}

# Overlays open and close on IPC command
open_and_close "emoji-picker" omarchy.emojis omarchy-emojis
open_and_close "menu" omarchy.menu omarchy-menu '{"menu":"root"}'
open_and_close "clipboard" omarchy.clipboard omarchy-clipboard

# The launcher does the full loop: open, search by typing, launch the top hit
if window_present "org.gnome.Calculator" >/dev/null 2>&1; then
  fail "launcher test starts with no calculator window" "a calculator window is already open"
fi

omarchy-shell shell summon omarchy.launcher >/dev/null
wait_until "launcher opens" 15 layer_present "omarchy-launcher"
sleep 1
screenshot "launcher-open"

wtype "calculator"
sleep 1
screenshot "launcher-search"
wtype -k Return

wait_until "launcher launches the top search hit" 60 window_present "org.gnome.Calculator"
wait_until "launcher closes after launching" 15 layer_absent "omarchy-launcher"

close_windows "org.gnome.Calculator"
wait_until "calculator window closes" 30 window_absent "org.gnome.Calculator"
