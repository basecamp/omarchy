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
grep -Fq 'syncCsdMaximizedState' "$cpp" || fail "CSD windows must drop Hyprland's fake map-time maximized state"
grep -Fq 'restoreFloatOnScreen' "$cpp" \
  || fail "CSD unmaximize must put the remembered float back on the work area immediately"
grep -Fq 'saveNormalFloat' "$cpp" \
  || fail "CSD maximize must remember the on-screen float before Hyprland eats it"
grep -Fq 'hyprbars:no_bar' "$cpp" || fail "fake maximized is cleared only for hyprbars:no_bar CSD clients"
grep -Fq 'm_suppressNextMaximize' "$cpp" || fail "clearing fake maximized must not be echoed back as a maximize request"
grep -Fq 'doLater' "$cpp" || fail "CSD min/max must apply on the event-loop idle, not inside the Wayland request"
grep -Fq 'm_isMapped' "$cpp" || fail "CSD maximize must not run setFullscreenMode before the window is mapped"
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
