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

grep -Fq 'hl.plugin.omarchy_minimize.restore' "$ws" || fail "restore unhides via omarchy-minimize, not a workspace move"
pass "restore uses in-place omarchy-minimize.restore"

if grep -Fq 'special:minimized' "$ws"; then
  fail "WindowService must not park windows on special:minimized"
fi
grep -Fq 'hl.plugin.omarchy_minimize.minimize' "$ws" || fail "minimize uses CWindow::setHidden through omarchy-minimize"
grep -Fq 'ipc.hidden === true' "$ws" || fail "minimized state is compositor hidden, not a special workspace name"

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
grep -Fq 'WindowModel.snapRect(geom, direction, 32)' "$ws" || fail "desktop snap insets 32px for hyprbars above the client box"
grep -Fq 'function moveTo' "$ws" || fail "caption drag uses WindowService.moveTo"
grep -Fq 'function _windowRecord' "$ws" || fail "taskbar windows are Hyprland records with addresses"
pass "snap and maximize use addressed Lua dispatchers through Hyprland.dispatch"

grep -Fq 'function cycleNext' "$ws" || fail "WindowService exposes cycleNext for Alt+Tab"
grep -Fq 'function commitCycle' "$ws" || fail "WindowService exposes commitCycle for Alt release"
grep -Fq 'function activateFromSwitcher' "$ws" || fail "WindowService exposes activateFromSwitcher for clickable Alt+Tab cards"
grep -Fq 'function cancelCycle' "$ws" || fail "WindowService can cancel an Alt+Tab cycle without commitCycle"
grep -Fq 'function toggleShowDesktop' "$ws" || fail "WindowService exposes toggleShowDesktop"
grep -Fq 'function pin' "$ws" || fail "WindowService exposes pin for the taskbar"
pass "WindowService exposes task-switcher, Show Desktop, and pin verbs"

grep -Fq 'target: "window"' "$ROOT/shell/shell.qml" || fail "shell registers a window IPC target"
grep -Fq 'function snapLeft(address: string)' "$ROOT/shell/shell.qml" || fail "window IPC snapLeft takes a window address"
grep -Fq 'function maximize(address: string)' "$ROOT/shell/shell.qml" || fail "window IPC maximize takes a window address"
grep -Fq 'function restoreOrMinimize(address: string)' "$ROOT/shell/shell.qml" || fail "window IPC restoreOrMinimize takes a window address"
grep -Fq 'function restoreNormal' "$ws" || fail "WindowService exposes restoreNormal to unsnap"
grep -Fq 'hyprctl", "-j", "monitors"' "$ws" || fail "monitor geometry is read from hyprctl -j monitors, not stale lastIpcObject"
grep -Fq 'hyprctl", "-j", "clients"' "$ws" || fail "client geometry for remember/restore is read from hyprctl -j clients"
if grep -E 'mon\.width \|\| ipc\.width|mon\.height \|\| ipc\.height' "$ws"; then
  fail "snap must not prefer Quickshell monitor size over compositor JSON"
fi
grep -Fq 'function restoreNormal(address: string)' "$ROOT/shell/shell.qml" || fail "window IPC restoreNormal takes a window address"
pass "shell registers a window IPC target"

run_node_test <<'JS'
const fs = require('fs')
const m = requireFromRoot('shell/services/WindowModel.js')

assertEqual(m.normalizeId('Firefox.desktop'), 'firefox', 'normalizeId strips .desktop and case')
assertEqual(m.windowAppId({ appId: 'org.mozilla.firefox' }), 'org.mozilla.firefox', 'windowAppId reads appId')
assertEqual(m.windowAppId({ class: 'foot' }), 'foot', 'windowAppId reads Hyprland class')

const pins = m.withPin([], { desktopId: 'firefox', name: 'Firefox', icon: 'firefox' })
assertEqual(pins.length, 1, 'withPin adds a pin')
assertEqual(m.withoutPin(pins, 'firefox').length, 0, 'withoutPin removes a pin')

const shipped = m.parsePins(fs.readFileSync(path.join(root, 'default/ultimate/taskbar-pins.json'), 'utf8'))
assertEqual(shipped[0].name, 'Chrome', 'shipped pins lead with Chrome')
assertEqual(shipped[1].name, 'Files', 'shipped pins include Files')
assert(
  shipped.every(pin => pin.id !== 'foot' && pin.desktopId !== 'foot' && pin.id !== 'vim'),
  'shipped pins do not make foot or vim first class'
)

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
const leftBar = m.snapRect(mon, 'l', 32)
assertEqual(leftBar.y, 32, 'desktop snap leaves 32px for hyprbars above the client box')
assertEqual(leftBar.height, 1008, 'desktop snap height is work area minus hyprbars')

const mixed = m.compositorMonitor({ width: 1920, height: 1080, reserved: [0, 0, 0, 40] })
assertEqual(mixed.height, 1080, 'compositorMonitor keeps the output height, not a gap-subtracted 1054')
const floated = m.defaultFloatRect(mon)
if (!(floated.width < 960 && floated.height < 1040)) {
  throw new Error('default float must not be a work-area half-tile')
}
const snapped = { x: 0, y: 0, width: 960, height: 1040 }
if (!m.isSnapped(snapped, mon, 8)) throw new Error('960x1040 at origin is the left snap')
const snappedBar = { x: 0, y: 32, width: 960, height: 1008 }
if (!m.isSnapped(snappedBar, mon, 8, 32)) throw new Error('960x1008 at y=32 is the desktop left snap')
if (m.isSnapped(floated, mon, 8)) throw new Error('default float must not count as snapped')
JS
