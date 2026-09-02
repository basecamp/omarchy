#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1788320383.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin"
cat >"$test_dir/bin/hyprctl" <<'STUB'
#!/bin/bash
echo reload >>"$HYPRCTL_CALLS"
STUB
chmod +x "$test_dir/bin/hyprctl"

home="$test_dir/home"
flag_dir="$home/.local/state/omarchy/toggles/hypr"
flag="$flag_dir/single-window-aspect-ratio.lua"
export HYPRCTL_CALLS="$test_dir/hyprctl-calls"

run_migration() {
  : >"$HYPRCTL_CALLS"
  HOME="$home" OMARCHY_PATH="$ROOT" PATH="$test_dir/bin:$PATH" \
    bash -euo pipefail "$migration" >/dev/null
}

mkdir -p "$flag_dir"

# No flag: people who never used the square toggle are left alone.
run_migration
[[ ! -e $flag ]] || fail "missing square-aspect flag stays missing"
[[ ! -s $HYPRCTL_CALLS ]] || fail "missing flag does not reload Hyprland"
pass "missing square-aspect flag is left alone"

# An already-converted marker is not rewritten, so a second run is a no-op.
printf '%s\n' "-- marker" >"$flag"
run_migration
grep -qx -- '-- marker' "$flag" || fail "converted marker is not rewritten"
[[ ! -s $HYPRCTL_CALLS ]] || fail "converted marker does not reload Hyprland"
pass "already-converted marker is a no-op"

# The old copied config becomes the half-tile marker and Hyprland reloads.
cat >"$flag" <<'LUA'
-- Avoid overly wide single-window layouts on wide screens.
hl.config({
  layout = {
    single_window_aspect_ratio = { 1, 1 },
  },
})
LUA
run_migration
if grep -q 'single_window_aspect_ratio' "$flag"; then
  fail "old square-aspect config is replaced with the half-tile marker"
fi
grep -q 'left or right half' "$flag" || fail "replacement is the packaged half-tile marker"
grep -qx reload "$HYPRCTL_CALLS" || fail "replacing the old config reloads Hyprland"
pass "old square-aspect config becomes the half-tile marker"
