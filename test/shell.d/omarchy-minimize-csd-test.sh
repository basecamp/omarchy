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
grep -Fq 'clearFakeMapMaximize' "$cpp" || fail "CSD map must unset fake maximized and size a real float"
grep -Fq 'onCsdMapped' "$cpp" || fail "fake maximize is cleared on map, not on every window rule update"
grep -Fq 'coversWorkArea' "$cpp" || fail "CSD map must also shrink a tiled work-area Chrome, not only FSMODE_MAXIMIZED"
grep -Fq 'floatWindow' "$cpp" || fail "cleared CSD map must float a tiled Chromium before sizing it"
grep -Fq '1200' "$cpp" || fail "cleared CSD map uses a float wide enough for Chromium CSD caption buttons"
! grep -Fq '880' "$cpp" || fail "CSD default float must not be 880; that clips min/max off Chrome's caption"
if grep -A2 'g_onUpdateRules' "$cpp" | grep -Fq 'onCsdMapped'; then
  fail "updateRules must not clear a real maximize"
fi
grep -Fq 'restoreFloatOnScreen' "$cpp" \
  || fail "CSD unmaximize must put the remembered float back on the work area immediately"
grep -Fq 'saveNormalFloat' "$cpp" \
  || fail "CSD maximize must remember the on-screen float before Hyprland eats it"
grep -Fq 'hyprbars:no_bar' "$cpp" || fail "fake maximized is cleared only for hyprbars:no_bar CSD clients"
grep -Fq 'm_suppressNextMaximize' "$cpp" || fail "clearing fake maximized must not be echoed back as a maximize request"
grep -Fq 'doLater' "$cpp" || fail "CSD min/max must apply on the event-loop idle, not inside the Wayland request"
grep -Fq 'finishAnimation' "$cpp" || fail "CSD maximize must stop the popin animation before the modeset"
grep -Fq 'm_isMapped' "$cpp" || fail "CSD maximize must not run setFullscreenMode before the window is mapped"
grep -Fq 'restoreCsdCaption' "$cpp" || fail "CSD caption restore exists so Chrome keeps min/max/close on its own row"
grep -Fq 'scheduleConfigure' "$cpp" || fail "wm_capabilities change must be followed by xdg_surface.configure"
grep -Fq 'XDG_TOPLEVEL_STATE_TILED_LEFT' "$cpp" \
  || fail "CSD configure must drop Hyprland fake tiled-on-all-sides or Chrome hides min/max"
grep -Fq 'ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE' "$cpp" \
  || fail "Hyprland SSD decoration replies must be overridden so Chrome draws min/max/close"
grep -Fq 'applyDecorationMode' "$cpp" \
  || fail "CSD clients must be told CLIENT_SIDE or hyprbars:no_bar deletes the three buttons"
grep -Fq 'setGetToplevelDecoration' "$cpp" \
  || fail "CLIENT_SIDE must be sent in get_toplevel_decoration, not after Chrome's first paint"
grep -Fq 'onGetDecoration' "$cpp" \
  || fail "decoration hook must still run Hyprland's onGetDecoration"
grep -Fq 'hideDecorationGlobals' "$cpp" \
  || fail "xdg-decoration must be hidden so Chrome ShouldUseCustomFrame draws min/max/close"
grep -Fq 'removeGlobal' "$cpp" \
  || fail "decoration globals must be removed, not answered SERVER_SIDE"
grep -Fq ':minimize,maximize,close' "$ROOT/install/user/first-run/gnome-theme.sh" \
  || fail "first-run must ship min/max/close; appmenu:close deletes Chrome CSD buttons"
if grep -E '^gsettings set .*appmenu:close' "$ROOT/install/user/first-run/gnome-theme.sh"; then
  fail "first-run must not set appmenu:close"
fi
grep -Fq ':minimize,maximize,close' "$ROOT/migrations/1787524000.sh" \
  || fail "existing installs must migrate off appmenu:close"
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
