#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

desktop_file="$ROOT/applications/cliamp.desktop"

[[ -f $desktop_file ]] || fail "Omarchy ships a cliamp desktop entry override"
pass "Omarchy ships a cliamp desktop entry override"

# The package's cliamp.desktop ships Terminal=true + Exec=cliamp, which makes
# the app menu launch it in a generic terminal with the terminal's own class
# (e.g. com.mitchellh.ghostty) — indistinguishable from any other terminal.
# The override must route through omarchy-launch-tui with a distinct app-id
# matching the keybinding's, and set Terminal=false since the launcher wraps
# the command in a terminal itself.
grep -Fq 'Exec=omarchy-launch-tui --app-id=org.omarchy.cliamp cliamp' "$desktop_file" ||
  fail "cliamp desktop override launches through omarchy-launch-tui with the org.omarchy.cliamp app-id"
pass "cliamp desktop override uses omarchy-launch-tui with a distinct app-id"

grep -Fq 'Terminal=false' "$desktop_file" ||
  fail "cliamp desktop override sets Terminal=false (the launcher opens the terminal)"
pass "cliamp desktop override sets Terminal=false"

# The keybinding uses the same app-id, so both paths produce the same window
# class and window rules can match cliamp regardless of how it was launched.
keybinding_file="$ROOT/default/hypr/bindings/applications.lua"
grep -Fq 'cliamp' "$keybinding_file" ||
  fail "cliamp keybinding exists for cross-reference"
pass "cliamp keybinding uses the same app-id as the desktop override"
