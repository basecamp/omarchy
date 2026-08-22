#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

desktop="$ROOT/default/ultimate/profiles/desktop.json"
power="$ROOT/default/ultimate/profiles/power-user.json"

jq -e '.mode == "desktop" and .features.taskbar == true and .features.topBar == false and .features.startMenu == true' "$desktop" >/dev/null \
  || fail "desktop profile enables taskbar and Start, not the top bar"
pass "desktop profile enables taskbar and Start, not the top bar"

jq -e '.mode == "power-user" and .features.taskbar == false and .features.topBar == true and .features.omarchyBindings == true' "$power" >/dev/null \
  || fail "power-user profile keeps tiling heritage flags"
pass "power-user profile keeps tiling heritage flags"

features=$(jq -r '.features | keys[]' "$desktop" | sort)
power_features=$(jq -r '.features | keys[]' "$power" | sort)
[[ $features == "$power_features" ]] || fail "both profiles declare the same feature keys"
pass "both profiles declare the same feature keys"

[[ -x $ROOT/bin/omarchy-mode ]] || fail "omarchy-mode is executable"
pass "omarchy-mode is executable"

grep -Fq 'GROUP_DESCRIPTIONS[mode]=' "$ROOT/bin/omarchy" || fail "omarchy lists the mode command group"
pass "omarchy lists the mode command group"

grep -Fq 'function overlayShellConfig' "$ROOT/shell/shell.qml" || fail "shell overlays Desktop Mode chrome"
grep -Fq 'omarchy.ultimate-taskbar' "$ROOT/shell/shell.qml" || fail "Desktop Mode overlay selects the taskbar plugin"
pass "shell overlays the taskbar without rewriting shell.json"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

HOME="$tmp" XDG_STATE_HOME="$tmp/.local/state" OMARCHY_ULTIMATE_MODE_SKIP_RELOAD=1 \
  "$ROOT/bin/omarchy-mode" get >"$tmp/out"
[[ $(<"$tmp/out") == "desktop" ]] || fail "mode get defaults to desktop" "actual: $(<"$tmp/out")"
pass "mode get defaults to desktop"

PATH="$ROOT/bin:$PATH" HOME="$tmp" XDG_STATE_HOME="$tmp/.local/state" OMARCHY_ULTIMATE_MODE_SKIP_RELOAD=1 \
  "$ROOT/bin/omarchy" mode get >"$tmp/routed"
[[ $(<"$tmp/routed") == "desktop" ]] || fail "omarchy mode routes to omarchy-mode" "actual: $(<"$tmp/routed")"
pass "omarchy mode routes to omarchy-mode"

HOME="$tmp" XDG_STATE_HOME="$tmp/.local/state" OMARCHY_ULTIMATE_MODE_SKIP_RELOAD=1 \
  "$ROOT/bin/omarchy-mode" set power-user >"$tmp/out"
[[ $(<"$tmp/out") == "power-user" ]] || fail "mode set writes power-user"
[[ $(<"$tmp/.local/state/omarchy/ultimate/mode") == "power-user" ]] || fail "mode set persists the state file"
pass "mode set persists power-user"

HOME="$tmp" XDG_STATE_HOME="$tmp/.local/state" OMARCHY_ULTIMATE_MODE_SKIP_RELOAD=1 \
  "$ROOT/bin/omarchy-mode" get >"$tmp/out"
[[ $(<"$tmp/out") == "power-user" ]] || fail "mode get reads the saved profile"
pass "mode get reads the saved profile"

HOME="$tmp" XDG_STATE_HOME="$tmp/.local/state" OMARCHY_ULTIMATE_MODE_SKIP_RELOAD=1 \
  "$ROOT/bin/omarchy-mode" set desktop >/dev/null
[[ $(<"$tmp/.local/state/omarchy/ultimate/mode") == "desktop" ]] || fail "mode set round-trips back to desktop"
pass "mode set round-trips back to desktop"

if HOME="$tmp" XDG_STATE_HOME="$tmp/.local/state" OMARCHY_ULTIMATE_MODE_SKIP_RELOAD=1 \
  "$ROOT/bin/omarchy-mode" set tiling >/dev/null 2>"$tmp/err"; then
  fail "mode set rejects unknown profiles"
fi
pass "mode set rejects unknown profiles"

# Overlay must not rewrite the on-disk shell.json; the CLI only touches the mode file.
mkdir -p "$tmp/.config/omarchy"
printf '%s\n' '{"version":1,"bar":{"id":"omarchy.bar","position":"top"}}' >"$tmp/.config/omarchy/shell.json"
HOME="$tmp" XDG_STATE_HOME="$tmp/.local/state" OMARCHY_ULTIMATE_MODE_SKIP_RELOAD=1 \
  "$ROOT/bin/omarchy-mode" set desktop >/dev/null
grep -Fq '"id":"omarchy.bar"' "$tmp/.config/omarchy/shell.json" || fail "mode set does not rewrite shell.json bar.id"
pass "mode set does not rewrite shell.json bar.id"
