#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

ws="$ROOT/shell/services/WindowService.qml"
[[ -f $ws ]] || fail "WindowService.qml exists"

if awk '
  $0 ~ /function restore\(/ { infn = 1 }
  infn && /movetoworkspacesilent special:minimized/ { found = 1 }
  infn && /^  function / && $0 !~ /function restore\(/ { infn = 0 }
  END { exit found ? 0 : 1 }
' "$ws"; then
  fail "restore must not move windows into special:minimized"
fi
pass "restore does not park windows in special:minimized"

grep -Fq '_restoreFromSpecial' "$ws" || fail "restore moves windows off the minimized special workspace"
pass "restore returns windows from the minimized special workspace"

grep -Fq 'hl.dsp.window.float' "$ws" || fail "snap uses hl.dsp.window.float instead of toggling tile state"
if grep -Fq 'togglefloating' "$ws"; then
  fail "snap must not togglefloating an already-floating window"
fi
if grep -E 'dispatchTokens.*movewindowpixel|movewindowpixel", "exact"' "$ws"; then
  fail "snap must not use classic movewindowpixel on the Lua dispatcher parser"
fi
if grep -Fq '"fullscreen", "2"' "$ws"; then
  fail "maximize must not dispatch classic fullscreen 2"
fi
grep -Fq 'mode = \"maximized\"' "$ws" || fail "maximize uses hl.dsp.window.fullscreen maximized"
grep -Fq 'special:minimized' "$ws" || fail "minimize parks on special:minimized via Lua move"
grep -Fq 'hl.dsp.window.float' "$ws" || fail "snap issues Lua float before resize/move"
grep -Fq 'property FileView pinFile' "$ws" || fail "pin FileView is a named property so QtObject can load"
grep -Fq 'import Quickshell.Hyprland' "$ws" || fail "WindowService reads Hyprland.toplevels for window addresses"
grep -Fq 'function _addresses' "$ws" || fail "WindowService can list window addresses for Alt+Tab"
grep -Fq 'Quickshell.execDetached' "$ws" || fail "hyprctl is fired with execDetached so QtObject does not own a Process child"
if grep -E '^[[:space:]]*[^/].*createQmlObject' "$ws"; then
  fail "WindowService must not create Process objects dynamically; they never start under QtObject"
fi
if grep -Fq 'property Process runner' "$ws"; then
  fail "WindowService must not serialize hyprctl through one Process; independent verbs get dropped"
fi
pass "snap and maximize use addressed Lua dispatchers"

grep -Fq 'function cycleNext' "$ws" || fail "WindowService exposes cycleNext for Alt+Tab"
grep -Fq 'function commitCycle' "$ws" || fail "WindowService exposes commitCycle for Alt release"
grep -Fq 'function toggleShowDesktop' "$ws" || fail "WindowService exposes toggleShowDesktop"
grep -Fq 'function pin' "$ws" || fail "WindowService exposes pin for the taskbar"
pass "WindowService exposes task-switcher, Show Desktop, and pin verbs"

grep -Fq 'target: "window"' "$ROOT/shell/shell.qml" || fail "shell registers a window IPC target"
grep -Fq 'function snapLeft(address: string)' "$ROOT/shell/shell.qml" || fail "window IPC snapLeft takes a window address"
grep -Fq 'function maximize(address: string)' "$ROOT/shell/shell.qml" || fail "window IPC maximize takes a window address"
pass "shell registers a window IPC target"

run_node_test <<'JS'
const m = requireFromRoot('shell/services/WindowModel.js')

assertEqual(m.normalizeId('Firefox.desktop'), 'firefox', 'normalizeId strips .desktop and case')
assertEqual(m.windowAppId({ appId: 'org.mozilla.firefox' }), 'org.mozilla.firefox', 'windowAppId reads appId')

const pins = m.withPin([], { desktopId: 'firefox', name: 'Firefox', icon: 'firefox' })
assertEqual(pins.length, 1, 'withPin adds a pin')
assertEqual(m.withoutPin(pins, 'firefox').length, 0, 'withoutPin removes a pin')

const groups = m.buildGroups(
  [
    { address: '0x1', appId: 'firefox', title: 'Mozilla Firefox' },
    { address: '0x2', appId: 'firefox', title: 'Firefox — tab' },
    { address: '0x3', appId: 'foot', title: 'foot' }
  ],
  [{ id: 'firefox', desktopId: 'firefox', name: 'Firefox', icon: 'firefox' }]
)
assertEqual(groups.length, 2, 'buildGroups combines pinned firefox windows and leaves foot unpinned')
assertEqual(groups[0].windows.length, 2, 'pinned firefox group contains both windows')
assertEqual(groups[0].pinned, true, 'firefox group is pinned')
assertEqual(groups[1].id, 'foot', 'unpinned running app is its own group')
JS
