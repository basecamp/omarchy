#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

HOOK="$ROOT/config/omarchy/hooks/bar-changed.d/gaps.sh"
[[ -f $HOOK ]] || fail "bar-changed hook exists: $HOOK"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Mock hyprctl: report a canned gaps_out (MOCK_GAPS) and capture the eval the
# hook issues, so we can assert the resulting gaps_out without a live compositor.
mkdir -p "$TMPDIR/bin"
cat >"$TMPDIR/bin/hyprctl" <<'MOCK'
#!/bin/bash
case "$*" in
  "getoption general:gaps_out -j") printf '{"css": "%s"}\n' "$MOCK_GAPS" ;;
  eval*) printf '%s\n' "$*" >>"$EVAL_LOG" ;;
esac
MOCK
chmod +x "$TMPDIR/bin/hyprctl"
export PATH="$TMPDIR/bin:$PATH"
export EVAL_LOG="$TMPDIR/eval.log"
export HYPRLAND_INSTANCE_SIGNATURE=test   # skip the runtime-dir lookup in the hook

# Run the hook and return the gaps_out it applied, as "top right bottom left".
# previous is the edge the bar moved off of (defaults to position: no move).
applied_gaps() {
  local position="$1" transparent="$2" start="$3" previous="${4:-$1}"
  : >"$EVAL_LOG"
  MOCK_GAPS="$start" bash "$HOOK" "$position" "$transparent" "$previous"
  grep -oE 'top = [0-9]+, right = [0-9]+, bottom = [0-9]+, left = [0-9]+' "$EVAL_LOG" \
    | tail -1 | grep -oE '[0-9]+' | paste -sd' '
}

check() {
  local position="$1" transparent="$2" start="$3" expected="$4" previous="${5:-$1}"
  local got
  got=$(applied_gaps "$position" "$transparent" "$start" "$previous")
  [[ $got == "$expected" ]] \
    || fail "bar-changed $position $transparent (from $previous) on [$start]" \
            "  got [$got], want [$expected]"
  pass "bar-changed $position $transparent (from $previous) on [$start] -> [$expected]"
}

# gaps_out order is top right bottom left.

# A transparent bar flushes its own edge to 0.
check top    true  "10 10 10 10" "0 10 10 10"
check bottom true  "10 10 10 10" "10 10 0 10"
check left   true  "10 10 10 10" "10 10 10 0"
check right  true  "10 10 10 10" "10 0 10 10"

# An opaque bar keeps the window gap on its edge (restoring an edge it had flushed).
check top    false "0 10 10 10"  "10 10 10 10"

# Only the bar's edge is touched: custom gaps on the other edges are preserved.
check top    true  "5 10 15 20"  "0 10 15 20"

# The no-gaps case (all zero) is preserved, not forced back to a default.
check top    true  "0 0 0 0"     "0 0 0 0"

# Moving the bar restores the edge it moved off of: from top to bottom, the top
# edge it had flushed is set back to the window gap.
check bottom true  "0 10 10 10"  "10 10 0 10"  top

# The same starting gaps without a move: the bar is on bottom and stayed there, so
# a hand-set top=0 is left exactly as the user configured it (not "restored").
check bottom true  "0 10 10 10"  "0 10 0 10"

pass "bar-changed hook keeps the window gap in step with the bar's edge and only restores the edge it moved off of"
