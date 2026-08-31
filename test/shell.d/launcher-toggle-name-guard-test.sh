#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_home="$test_tmp/home"
stub_bin="$test_tmp/bin"
test_root="$test_tmp/omarchy"
mkdir -p "$test_home/.local/share/applications" \
  "$test_home/.local/state/omarchy/toggles/hypr" \
  "$stub_bin" \
  "$test_root/default/hypr/toggles"

for stub in hyprctl update-desktop-database omarchy-notification-send; do
  printf '#!/bin/bash\n:\n' >"$stub_bin/$stub"
  chmod +x "$stub_bin/$stub"
done

echo '-- example flag' >"$test_root/default/hypr/toggles/example.lua"

run_toggle() {
  HOME="$test_home" OMARCHY_PATH="$test_root" PATH="$stub_bin:/usr/bin" \
    "$ROOT/bin/omarchy-hyprland-toggle" "$@"
}

run_remove() {
  HOME="$test_home" OMARCHY_REMOVE_NOTIFY=false PATH="$stub_bin:/usr/bin" \
    "$ROOT/bin/omarchy-webapp-remove" "$@"
}

# A slashed toggle name used to leave the toggle directory. The toggle
# directory must exist for the escape to resolve, so keep it in place.
victim="$test_home/.local/state/omarchy/victim.lua"
echo 'keep me' >"$victim"

output=$(run_toggle '../../victim' off 2>&1) &&
  fail "hyprland-toggle rejects a flag name containing a slash"
[[ $output == *"Flag name cannot contain '/'"* ]] ||
  fail "hyprland-toggle says why it refused a slashed name" "$output"
[[ -f $victim ]] ||
  fail "hyprland-toggle leaves a file outside the toggle directory alone"
pass "hyprland-toggle rejects a flag name that escapes the toggle directory"

flag="$test_home/.local/state/omarchy/toggles/hypr/example.lua"

run_toggle example on >/dev/null
[[ -f $flag ]] || fail "hyprland-toggle still enables a plain flag name"
run_toggle example off >/dev/null
[[ ! -f $flag ]] || fail "hyprland-toggle still disables a plain flag name"
pass "hyprland-toggle still toggles plain flag names"

# A slashed web app name used to escape the applications directory through
# the rebuilt fallback path.
victim="$test_home/.local/victim.desktop"
echo '[Desktop Entry]' >"$victim"

output=$(run_remove '../../victim' 2>&1) &&
  fail "webapp-remove rejects an app name containing a slash"
[[ $output == *"App name cannot contain '/'"* ]] ||
  fail "webapp-remove says why it refused a slashed name" "$output"
[[ -f $victim ]] ||
  fail "webapp-remove leaves a file outside the applications directory alone"
pass "webapp-remove rejects an app name that escapes the applications directory"
