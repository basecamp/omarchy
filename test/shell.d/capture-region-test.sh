#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin"

# One monitor with two overlapping windows on its active workspace: a tiled one
# filling the left half and a floating one sitting inside it.
cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash

case $1 in
monitors)
  printf '%s\n' '[{"name":"DP-1","focused":true,"x":0,"y":0,"width":2560,"height":1440,"scale":1,"transform":0,"activeWorkspace":{"id":1}}]'
  ;;
clients)
  printf '%s\n' '[{"workspace":{"id":1},"at":[0,0],"size":[1280,1440]},{"workspace":{"id":1},"at":[400,500],"size":[400,300]}]'
  ;;
cursorpos)
  printf '%s\n' "${OMARCHY_TEST_CURSOR:-500, 600}"
  ;;
esac
SH

cat >"$stub_bin/hyprpicker" <<'SH'
#!/bin/bash
sleep 5
SH

# slurp answers with whatever the test is simulating; a bare click comes back as
# a 1x1 rectangle at the pointer.
cat >"$stub_bin/slurp" <<'SH'
#!/bin/bash
cat >/dev/null
printf '%s\n' "${OMARCHY_TEST_SLURP:-500,600 1x1}"
SH

chmod +x "$stub_bin"/*
export PATH="$stub_bin:$ROOT/bin:$PATH"
export XDG_RUNTIME_DIR="$tmp_dir"

selection=$("$ROOT/bin/omarchy-capture-region" smart)
[[ $selection == "400,500 400x300" ]] ||
  fail "a bare click snaps to the smallest rectangle under the pointer" "actual: $selection"
pass "a bare click snaps to the smallest rectangle under the pointer"

# A click in the part of the monitor no window covers still has the monitor to
# fall back on.
bare=$(OMARCHY_TEST_SLURP="2000,200 1x1" "$ROOT/bin/omarchy-capture-region" smart)
[[ $bare == "0,0 2560x1440" ]] ||
  fail "a bare click outside every window snaps to the monitor" "actual: $bare"
pass "a bare click outside every window snaps to the monitor"

# A real drag is the user's own rectangle and must survive untouched.
drag=$(OMARCHY_TEST_SLURP="450,550 120x90" "$ROOT/bin/omarchy-capture-region" smart)
[[ $drag == "450,550 120x90" ]] ||
  fail "a dragged selection is left alone" "actual: $drag"
pass "a dragged selection is left alone"

# --match-monitor reports the monitor by name when the pick covers all of it.
named=$(OMARCHY_TEST_SLURP="2000,200 1x1" "$ROOT/bin/omarchy-capture-region" smart --match-monitor)
[[ $named == "monitor:DP-1" ]] ||
  fail "a monitor-sized pick is reported by name" "actual: $named"
pass "a monitor-sized pick is reported by name"
