#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

cpp="$ROOT/default/hypr/plugins/omarchy-minimize/main.cpp"
[[ -f $cpp ]] || fail "omarchy-minimize plugin source exists"

grep -Fq 'applyRequestedMinimize' "$cpp" || fail "CSD minimize applicator exists"
grep -Fq 'applyRequestedMaximize' "$cpp" || fail "CSD maximize applicator exists"
grep -Fq 'applyRequestedState' "$cpp" || fail "one stateChanged watcher applies min and max"
grep -Fq 'requestsMaximize' "$cpp" || fail "omarchy-minimize honors xdg/X11 CSD maximize requests"
grep -Fq 'FSMODE_MAXIMIZED' "$cpp" || fail "CSD maximize uses Hyprland maximized fullscreen, not omarchy-shell"
if grep -Fq 'omarchy-shell' "$cpp"; then
  fail "omarchy-minimize must not exec omarchy-shell from the compositor"
fi
if grep -Fq 'o.bind("mouse:272"' "$ROOT/default/hypr/bindings/desktop.lua"; then
  fail "global left-click must not bind dismissOutside; that bind eats CSD min/max/close"
fi
grep -Fq 'quick_click' "$ROOT/test/acceptance.d/hyprbars-pointer-proof.py" \
  || fail "hyprbars pointer proof clicks maximize faster than hover dwell"
grep -Fq 'hyprbars maximize click maximizes' "$ROOT/test/acceptance.d/hyprbars-pointer-proof.py" \
  || fail "hyprbars pointer proof clicks □ to maximize, not only hover"
grep -Fq 'hyprbars minimize click hides' "$ROOT/test/acceptance.d/hyprbars-pointer-proof.py" \
  || fail "hyprbars pointer proof clicks – to minimize"
grep -Fq 'csd maximize click maximizes' "$ROOT/test/acceptance.d/csd-caption-pointer-proof.py" \
  || fail "CSD caption pointer proof clicks the client maximize square"
grep -Fq 'refusing to AbsPointer Cursor' "$ROOT/test/acceptance.d/csd-caption-pointer-proof.py" \
  || fail "CSD caption pointer proof refuses to AbsPointer Cursor"
grep -Fq 'restore_cursor' "$ROOT/test/acceptance.d/csd-caption-pointer-proof.py" \
  || fail "CSD caption pointer proof restores Cursor in finally"
pass "CSD min/max protocol and caption-click proofs are wired"
