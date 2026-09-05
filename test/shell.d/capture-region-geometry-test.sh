#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Stand in for the compositor. Only "monitors -j" is asked for on the fullscreen
# path, so a fixed payload is the whole dependency: no slurp, no hyprpicker, no
# Wayland. $OMARCHY_TEST_MONITORS carries the monitor list under test.
printf '%s\n' \
  '#!/bin/bash' \
  'printf "%s\n" "$OMARCHY_TEST_MONITORS"' \
  >"$tmpdir/hyprctl"
chmod +x "$tmpdir/hyprctl"

# One 1920x1080 output at scale 1, so a rotated result is exactly the mode the
# other way round and the assertion cannot be satisfied by rounding.
monitors_with_transform() {
  printf '[{"name":"DP-1","focused":true,"x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":%s,"activeWorkspace":{"id":1}}]' "$1"
}

geo_for_transform() {
  OMARCHY_TEST_MONITORS="$(monitors_with_transform "$1")" \
    PATH="$tmpdir:$ROOT/bin:$PATH" omarchy-capture-region fullscreen
}

# Hyprland reports the mode, not the logical size, so every quarter-turn
# transform has to come back measured the other way round. 1 and 3 are the
# plain rotations; 5 and 7 are the same two turns with a flip, and those are
# the ones a "$t == 1 or $t == 3" test used to miss.
for transform in 1 3 5 7; do
  geo=$(geo_for_transform "$transform")
  [[ $geo == "0,0 1080x1920" ]] ||
    fail "transform $transform is measured as rotated" "expected: 0,0 1080x1920
actual:   $geo"
done

pass "every quarter-turn transform is measured as rotated"

# The even transforms are upright (0 and 4 unflipped/flipped, 2 and 6 half a
# turn), so the mode passes through unswapped.
for transform in 0 2 4 6; do
  geo=$(geo_for_transform "$transform")
  [[ $geo == "0,0 1920x1080" ]] ||
    fail "transform $transform is measured as upright" "expected: 0,0 1920x1080
actual:   $geo"
done

pass "upright transforms keep the mode as reported"

# A monitor list without the key at all must not read as rotated.
geo=$(OMARCHY_TEST_MONITORS='[{"name":"DP-1","focused":true,"x":0,"y":0,"width":1920,"height":1080,"scale":1,"activeWorkspace":{"id":1}}]' \
  PATH="$tmpdir:$ROOT/bin:$PATH" omarchy-capture-region fullscreen)
[[ $geo == "0,0 1920x1080" ]] ||
  fail "a monitor with no transform key is measured as upright" "$geo"

pass "a missing transform key is treated as upright"

# --match-monitor matches the picked geometry back to a monitor by name. It
# compares against the same format_geo, so a rotated output whose geometry was
# measured the wrong way round could never match itself.
name=$(OMARCHY_TEST_MONITORS="$(monitors_with_transform 5)" \
  PATH="$tmpdir:$ROOT/bin:$PATH" omarchy-capture-region fullscreen --match-monitor)
[[ $name == "monitor:DP-1" ]] ||
  fail "a flipped-and-rotated monitor matches itself by name" "expected: monitor:DP-1
actual:   $name"

pass "--match-monitor recognizes a flipped-and-rotated output"
