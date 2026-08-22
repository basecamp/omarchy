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

grep -Fq 'Hyprland.focusedWorkspace' "$ws" || fail "restore uses Hyprland.focusedWorkspace, not a bash subshell"
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
grep -Fq 'Hyprland.dispatch' "$ws" || fail "window verbs use Hyprland.dispatch, not shelling out to hyprctl"
if grep -Fq 'Quickshell.execDetached' "$ws"; then
  fail "WindowService must not execDetached hyprctl; dispatchers go through Hyprland.dispatch"
fi
if grep -E '^[[:space:]]*[^/].*createQmlObject' "$ws"; then
  fail "WindowService must not create Process objects dynamically; they never start under QtObject"
fi
if grep -Fq 'property Process runner' "$ws"; then
  fail "WindowService must not serialize hyprctl through one Process; independent verbs get dropped"
fi
if awk '
  $0 ~ /function _snap\(/ { infn = 1 }
  infn && /bash/ { found = 1 }
  infn && /^  function / && $0 !~ /function _snap\(/ { infn = 0 }
  END { exit found ? 0 : 1 }
' "$ws"; then
  fail "snap must not assemble bash -c around a raw window address"
fi
if awk '
  $0 ~ /function restore\(/ { infn = 1 }
  infn && /bash/ { found = 1 }
  infn && /^  function / && $0 !~ /function restore\(/ { infn = 0 }
  END { exit found ? 0 : 1 }
' "$ws"; then
  fail "restore must not assemble bash -c around a raw window address"
fi
grep -Fq 'WindowModel.snapRect' "$ws" || fail "snap geometry comes from WindowModel.snapRect (LTRB reserved)"
grep -Fq 'function moveTo' "$ws" || fail "caption drag uses WindowService.moveTo"
grep -Fq 'function _windowRecord' "$ws" || fail "taskbar windows are Hyprland records with addresses"
pass "snap and maximize use addressed Lua dispatchers through Hyprland.dispatch"

grep -Fq 'function cycleNext' "$ws" || fail "WindowService exposes cycleNext for Alt+Tab"
grep -Fq 'function commitCycle' "$ws" || fail "WindowService exposes commitCycle for Alt release"
grep -Fq 'function activateFromSwitcher' "$ws" || fail "WindowService exposes activateFromSwitcher for clickable Alt+Tab cards"
grep -Fq 'function toggleShowDesktop' "$ws" || fail "WindowService exposes toggleShowDesktop"
grep -Fq 'function pin' "$ws" || fail "WindowService exposes pin for the taskbar"
pass "WindowService exposes task-switcher, Show Desktop, and pin verbs"

grep -Fq 'target: "window"' "$ROOT/shell/shell.qml" || fail "shell registers a window IPC target"
grep -Fq 'function snapLeft(address: string)' "$ROOT/shell/shell.qml" || fail "window IPC snapLeft takes a window address"
grep -Fq 'function maximize(address: string)' "$ROOT/shell/shell.qml" || fail "window IPC maximize takes a window address"
grep -Fq 'function restoreOrMinimize(address: string)' "$ROOT/shell/shell.qml" || fail "window IPC restoreOrMinimize takes a window address"
pass "shell registers a window IPC target"

run_node_test <<'JS'
const m = requireFromRoot('shell/services/WindowModel.js')

assertEqual(m.normalizeId('Firefox.desktop'), 'firefox', 'normalizeId strips .desktop and case')
assertEqual(m.windowAppId({ appId: 'org.mozilla.firefox' }), 'org.mozilla.firefox', 'windowAppId reads appId')
assertEqual(m.windowAppId({ class: 'foot' }), 'foot', 'windowAppId reads Hyprland class')

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

const mon = { width: 1920, height: 1080, reserved: [0, 0, 0, 40] }
const area = m.workArea(mon)
assertEqual(area.x, 0, 'LTRB reserved left is x')
assertEqual(area.y, 0, 'LTRB reserved top is y')
assertEqual(area.width, 1920, 'work width is monitor minus left/right')
assertEqual(area.height, 1040, 'work height subtracts the bottom taskbar, not a left inset')
const left = m.snapRect(mon, 'l')
assertEqual(left.x, 0, 'snap left starts at the work-area x')
assertEqual(left.width, 960, 'snap left is half the work area')
assertEqual(left.height, 1040, 'snap left height respects the bottom reserved edge')
const right = m.snapRect(mon, 'r')
assertEqual(right.x, 960, 'snap right starts at the midpoint')
assertEqual(right.width, 960, 'snap right takes the remaining half')
assertEqual(right.height, 1040, 'snap right height respects the bottom reserved edge')
JS
