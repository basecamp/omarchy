#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

flags="$ROOT/config/obsidian/user-flags.conf"
[[ -f $flags ]] || fail "obsidian user-flags.conf is shipped"

# Single-dash -disable-gpu is not a valid Electron flag (#9781).
if grep -E '^-disable-gpu' "$flags" >/dev/null; then
  fail "obsidian flags must not use a single-dash -disable-gpu"
fi
grep -Fx -- '--disable-gpu' "$flags" >/dev/null ||
  fail "obsidian flags include --disable-gpu"
grep -E '^--ozone-platform-hint=' "$flags" >/dev/null ||
  fail "obsidian flags include an ozone platform hint for Wayland"
grep -Fx -- '--enable-wayland-ime' "$flags" >/dev/null ||
  fail "obsidian flags keep wayland IME support"
pass "obsidian user-flags.conf uses valid Electron flags"

mullvad="$ROOT/default/hypr/apps/mullvad.lua"
[[ -f $mullvad ]] || fail "mullvad app rule is shipped"
grep -E 'float\s*=\s*true' "$mullvad" >/dev/null || fail "mullvad rule floats the window"
grep -E 'center\s*=\s*true' "$mullvad" >/dev/null || fail "mullvad rule centers the window"
grep -E 'Mullvad VPN|mullvad-vpn' "$mullvad" >/dev/null ||
  fail "mullvad rule matches Mullvad VPN window class/title"
pass "mullvad app rule floats and centers the VPN window"

# default.hypr.apps require_all loads every .lua under default/hypr/apps.
apps_loader="$ROOT/default/hypr/apps.lua"
grep -F 'default/hypr/apps' "$apps_loader" >/dev/null ||
  fail "apps.lua loads the apps directory"
pass "mullvad.lua is picked up by default.hypr.apps require_all"
