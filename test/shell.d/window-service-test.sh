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
grep -Fq 'function _hyprbarsInset' "$ws" || fail "snap inset follows hyprbars:no_bar CSD clients"
grep -Fq 'WindowModel.coversWorkArea' "$ws" || fail "unmaximize must not restore a work-area-covering box as the normal float"
grep -Fq 'if (!root._knownAddresses[target]) return false' "$ws" \
  || fail "a new tiled Chromium must not count as maximized just because it covers the work area"
grep -Fq 'WindowModel.hyprbarsSnapInset' "$ws" || fail "desktop snap asks WindowModel for hyprbars inset"
if grep -Fq 'WindowModel.snapRect(geom, direction, 32)' "$ws"; then
  fail "CSD clients must not always reserve 32px for hyprbars"
fi
grep -Fq 'function moveTo' "$ws" || fail "caption drag uses WindowService.moveTo"
grep -Fq 'function _windowRecord' "$ws" || fail "taskbar windows are Hyprland records with addresses"
pass "snap and maximize use addressed Lua dispatchers through Hyprland.dispatch"

grep -Eq '^  function activate\(' "$ws" || fail "WindowService exposes activate for Alt+Tab and taskbar"
grep -Fq 'function activateAtCursor' "$ws" || fail "WindowService exposes activateAtCursor for Start click-through"
grep -Fq 'function activateAtCursorSoon' "$ws" || fail "Start dismiss delays activateAtCursor until overlay unmap returns"
grep -Fq 'hl.get_cursor_pos' "$ws" || fail "activateAtCursor hit-tests with compositor cursor position, not a QML hyprctl"
grep -Fq 'activateAtCursorSoon' "$ROOT/shell/plugins/ultimate-start/Start.qml" || fail "Start close re-activates the window under the cursor after unmap"
grep -Fq 'function cycleNext' "$ws" || fail "WindowService exposes cycleNext for Alt+Tab"
grep -Fq 'function commitCycle' "$ws" || fail "WindowService exposes commitCycle for Alt release"
grep -Fq 'function activateFromSwitcher' "$ws" || fail "WindowService exposes activateFromSwitcher for clickable Alt+Tab cards"
grep -Fq 'function cancelCycle' "$ws" || fail "WindowService can cancel an Alt+Tab cycle without commitCycle"
if awk '
  $0 ~ /function activateFromSwitcher\(/ { infn = 1 }
  infn && /root.activate/ { found = 1 }
  infn && /^  function / && $0 !~ /function activateFromSwitcher\(/ { infn = 0 }
  END { exit found ? 0 : 1 }
' "$ws"; then
  :
else
  fail "activateFromSwitcher must activate the clicked address, not only restore"
fi
if awk '
  $0 ~ /function commitCycle\(/ { infn = 1 }
  infn && /root.activate/ { found = 1 }
  infn && /^  function / && $0 !~ /function commitCycle\(/ { infn = 0 }
  END { exit found ? 0 : 1 }
' "$ws"; then
  :
else
  fail "commitCycle must activate the highlighted address, not only restore"
fi
if awk '
  $0 ~ /function toggleFromTaskbar\(/ { infn = 1 }
  infn && /root.activate/ { found = 1 }
  infn && /^  function / && $0 !~ /function toggleFromTaskbar\(/ { infn = 0 }
  END { exit found ? 0 : 1 }
' "$ws"; then
  :
else
  fail "inactive taskbar click must activate, not only restore"
fi
grep -Fq 'if (root.isMinimized(address)) return root.activate(address)' "$ws" \
  || fail "taskbar click on a minimized window must restore, even if Hyprland still marks it active"
grep -Fq 'function _recordFromClient' "$ws" \
  || fail "taskbar keeps setHidden windows that dropped out of Hyprland.toplevels"
grep -Fq 'Number(c.fullscreen || 0) > 0' "$ws" \
  || fail "new-window placement must not restomp a just-maximized client"
grep -Fq 'if (root.isMaximized(addr))' "$ws" \
  || fail "placement must not restomp a window that is already work-area sized"
grep -Fq 'kinds[addr] = "max"' "$ws" \
  || fail "clientsIpc fullscreen=1 records _placedKind max for CSD maximize"
grep -Fq 'function _restoreFloatOnScreen' "$ws" \
  || fail "unmaximize restores the pre-max float onto the work area"
grep -Fq 'function _queueFloatRestore' "$ws" \
  || fail "late compositor stomps after unmaximize must re-clamp chrome onto the work area"
grep -Fq 'restoreFloatRetryTimer' "$ws" \
  || fail "float restore retries after CSD configure can move chrome off-screen"
grep -Fq 'WindowModel.clampRect(bounds, geom)' "$ws" \
  || fail "_applyRect clamps so restore cannot place chrome above the monitor"
grep -Fq 'prevFs === 1 && fs === 0' "$ws" \
  || fail "CSD unmaximize must restore the remembered float, not Hyprland's last-floating box"
grep -Fq 'function toggleShowDesktop' "$ws" || fail "WindowService exposes toggleShowDesktop"
grep -Fq 'function pin' "$ws" || fail "WindowService exposes pin for the taskbar"
pass "WindowService exposes task-switcher, Show Desktop, and pin verbs"

grep -Fq 'target: "window"' "$ROOT/shell/shell.qml" || fail "shell registers a window IPC target"
grep -Fq 'function _finish' "$ws" || fail "WindowService writers return through a recorded result"
grep -Fq 'changed: true, error: null' "$ws" || fail "WindowService success is { changed, error: null }"
grep -Fq 'function invoke' "$ROOT/shell/services/CapabilityBroker.qml" || fail "broker dispatches window verbs"
grep -Fq 'function windowIpc' "$ROOT/shell/shell.qml" || fail "window IPC serializes the service result"
if awk '
  $0 ~ /IpcHandler \{/ { ipc = 1 }
  ipc && /target: "window"/ { win = 1 }
  win && /function minimize\(address: string\): string/ { infn = 1 }
  infn && /return "ok"/ { found = 1 }
  infn && /function / && $0 !~ /function minimize/ { infn = 0 }
  END { exit found ? 0 : 1 }
' "$ROOT/shell/shell.qml"; then
  fail "window IPC minimize must not return a bare ok string"
fi
grep -Fq 'function snapTo' "$ws" || fail "WindowService exposes snapTo for quarters and the layout chooser"
grep -Fq 'function snapArrow' "$ws" || fail "WindowService exposes snapArrow for Win+Arrow"
grep -Fq 'function aeroDragEnd' "$ws" || fail "WindowService exposes aeroDragEnd for title-bar drag-to-edge"
grep -Fq 'function saveLayout' "$ws" || fail "WindowService exposes saveLayout"
grep -Fq 'function restoreLayout' "$ws" || fail "WindowService exposes restoreLayout"
grep -Fq 'rect = root._clientRect(list[i])' "$ws" || fail "saveLayout reads compositor client boxes, not stale lastIpcObject"
grep -Fq 'function snapChooser' "$ROOT/shell/shell.qml" || fail "window IPC snapChooser summons the layout overlay"
grep -Fq 'function createDesktop' "$ws" || fail "WindowService exposes createDesktop for virtual desktops"
grep -Fq 'function moveToMonitor' "$ws" || fail "WindowService exposes moveToMonitor"
grep -Fq 'root._setPlacedKind(target, "full")' "$ws" || fail "toggleFullscreen records _placedKind full"
grep -Fq 'mode = \"fullscreen\", action = \"set\", layout_aware = false' "$ws" \
  || fail "F11 fullscreen must set layout_aware=false exclusive fullscreen, not toggle"
grep -Fq 'function taskView' "$ROOT/shell/shell.qml" || fail "window IPC taskView summons Task View"
grep -Fq 'aeroDragEnd(address: string, x: string, y: string)' "$ROOT/shell/shell.qml" || fail "aeroDragEnd IPC takes cursor coordinates"
grep -Fq '_addressesOnDesktop' "$ws" || fail "Alt+Tab cycles windows on the current desktop"
grep -Fq 'function neighborMonitor' "$ROOT/shell/services/WindowModel.js" || fail "WindowModel can name the neighboring monitor"
grep -Fq 'follow = false' "$ws" || fail "moveToDesktop does not steal the current desktop"
grep -Fq 'function close(address: string)' "$ROOT/shell/shell.qml" || fail "window IPC close takes a window address"
grep -Fq 'function cycleSnapshot' "$ROOT/shell/shell.qml" || fail "window IPC cycleSnapshot exposes the live Alt+Tab highlight"
grep -Fq 'function maximize(address: string)' "$ROOT/shell/shell.qml" || fail "window IPC maximize takes a window address"
grep -Fq 'function restoreOrMinimize(address: string)' "$ROOT/shell/shell.qml" || fail "window IPC restoreOrMinimize takes a window address"
grep -Fq 'function restoreNormal' "$ws" || fail "WindowService exposes restoreNormal to unsnap"
grep -Fq 'if (root._placedKind[target] === "max") return true' "$ws" \
  || fail "isMaximized trusts the maximize verb; lastIpcObject and the clients poll lag behind it"
grep -Fq 'if (live && Number(live.fullscreen) === 1) return true' "$ws" \
  || fail "isMaximized still reads compositor fullscreen when this service did not place the window"
if awk '
  $0 ~ /function aeroDragEnd\(/ { infn = 1 }
  infn && /placed === "max"/ { placed = 1 }
  infn && /root.unmaximize\(target\)/ { unsetmax = 1 }
  infn && /^  function / && $0 !~ /function aeroDragEnd\(/ { infn = 0 }
  END { exit (placed && unsetmax) ? 0 : 1 }
' "$ws"; then
  :
else
  fail "aeroDragEnd interior drop must restore from _placedKind, then unmaximize if the poll is still the pre-max float"
fi
grep -Fq 'root._setPlacedKind(target, "max")' "$ws" || fail "maximize records _placedKind so Aero drag-away does not wait on lastIpcObject"
grep -Fq 'hyprctl", "-j", "monitors"' "$ws" || fail "monitor geometry is read from hyprctl -j monitors, not stale lastIpcObject"
grep -Fq 'hyprctl", "-j", "clients"' "$ws" || fail "client geometry for remember/restore is read from hyprctl -j clients"
if grep -E 'mon\.width \|\| ipc\.width|mon\.height \|\| ipc\.height' "$ws"; then
  fail "snap must not prefer Quickshell monitor size over compositor JSON"
fi
grep -Fq 'function restoreNormal(address: string)' "$ROOT/shell/shell.qml" || fail "window IPC restoreNormal takes a window address"
grep -Fq 'function activate(address: string)' "$ROOT/shell/shell.qml" \
  || fail "window IPC activate takes a window address"
if awk '
  $0 ~ /function commitCycle\(\): string/ { infn = 1 }
  infn && /cycleList/ { captured = 1 }
  infn && /shell.hide\("omarchy.ultimate-task-switcher"\)/ { hid = 1 }
  infn && captured && hid { found = 1 }
  infn && /^    function / && $0 !~ /function commitCycle/ { infn = 0 }
  END { exit found ? 0 : 1 }
' "$ROOT/shell/shell.qml"; then
  :
else
  fail "commitCycle must capture the highlighted address before hiding the overlay"
fi
pass "shell registers a window IPC target"

run_node_test <<'JS'
const fs = require('fs')
const m = requireFromRoot('shell/services/WindowModel.js')

assertEqual(m.normalizeId('Firefox.desktop'), 'firefox', 'normalizeId strips .desktop and case')
assertEqual(m.windowAppId({ appId: 'org.mozilla.firefox' }), 'org.mozilla.firefox', 'windowAppId reads appId')
assertEqual(m.windowAppId({ class: 'foot' }), 'foot', 'windowAppId reads Hyprland class')
assert(m.isLockSurface({ class: 'org.omarchy.screensaver' }), 'screensaver class is a lock surface')
assert(m.isLockSurface({ initialClass: 'org.omarchy.screensaver', class: 'foot' }), 'screensaver initialClass is a lock surface even if class looks like foot')
assert(!m.isLockSurface({ class: 'foot' }), 'ordinary foot is not a lock surface')
assertEqual(m.hyprbarsSnapInset({ class: 'foot' }), 32, 'SSD clients reserve hyprbars height')
assertEqual(m.hyprbarsSnapInset({ class: 'chromium' }), 0, 'Chromium CSD does not reserve hyprbars')
assertEqual(m.hyprbarsSnapInset({ class: 'cursor' }), 0, 'Cursor CSD does not reserve hyprbars')
assertEqual(m.hyprbarsSnapInset({ class: 'chrome-www.youtube.com__-Default' }), 0, 'YouTube PWAs keep Chromium CSD inset 0')
assertEqual(m.hyprbarsSnapInset({ class: 'chrome-app.zoom.us__wc_home-Default' }), 0, 'Zoom PWAs keep Chromium CSD inset 0')
assertEqual(m.hyprbarsSnapInset({ class: 'xyz-app.zoom.us__wc_home' }), 0, 'Zoom PWA class without chrome- still insets 0')
assertEqual(m.hyprbarsSnapInset({ class: 'zoom' }), 32, 'native Zoom client keeps hyprbars inset')
assertEqual(m.usesWaylandCsd({ class: 'zenity' }), false, 'zenity is not the Zen browser')
assertEqual(m.usesWaylandCsd({ class: 'org.gnome.Nautilus' }), true, 'Nautilus uses GTK CSD')
assertEqual(m.usesWaylandCsd({ class: 'Nautilus' }), true, 'Files class Nautilus uses GTK CSD')
assertEqual(m.hyprbarsSnapInset({ class: 'org.gnome.Nautilus' }), 0, 'Files does not reserve a second hyprbars row')

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
const tl = m.snapRect(mon, 'tl', 32)
assertEqual(tl.x, 0, 'top-left quarter starts at work-area x')
assertEqual(tl.y, 32, 'top-left quarter sits under hyprbars')
assertEqual(tl.width, 960, 'top-left quarter is half width')
assertEqual(tl.height, 504, 'top-left quarter is half of the titled work height')
const br = m.snapRect(mon, 'br', 32)
assertEqual(br.x, 960, 'bottom-right quarter starts at the midpoint')
assertEqual(br.y, 32 + 504, 'bottom-right quarter sits under the top quarter')
assertEqual(br.height, 504, 'bottom-right quarter consumes the remaining titled height')
assertEqual(m.snapKind({ x: 0, y: 32, width: 960, height: 1008 }, mon, 8, 32), 'l', 'full left half is kind l')
assertEqual(m.snapKind(tl, mon, 8, 32), 'tl', 'top-left rect is kind tl')
assertEqual(m.nextSnap('float', 'l'), 'l', 'Win+Left from float is left half')
assertEqual(m.nextSnap('float', 'u'), 'max', 'Win+Up from float is maximize')
assertEqual(m.nextSnap('l', 'u'), 'tl', 'Win+Up from left half is top-left')
assertEqual(m.nextSnap('l', 'd'), 'bl', 'Win+Down from left half is bottom-left')
assertEqual(m.nextSnap('max', 'd'), 'normal', 'Win+Down from maximize restores')
assertEqual(m.nextSnap('float', 'd'), 'min', 'Win+Down from float minimizes')
assertEqual(m.aeroZone({ x: 0, y: 0 }, mon), 'tl', 'cursor in the top-left corner is top-left')
assertEqual(m.aeroZone({ x: 0, y: 200 }, mon), 'l', 'cursor on the left edge is left half')
assertEqual(m.aeroZone({ x: 400, y: 0 }, mon), 'max', 'cursor on the top edge is maximize')
assertEqual(m.aeroZone({ x: 400, y: 200 }, mon), '', 'interior cursor does not snap')
assertEqual(m.aeroZone({ x: 960, y: 540 }, mon), '', 'cursor in the middle of a maximized window does not snap')
const saved = m.captureLayout([
  { address: '0x1', appId: 'foot', title: 'left', x: 0, y: 32, width: 960, height: 1008, fullscreen: 0 },
  { address: '0x2', appId: 'foot', title: 'right', x: 960, y: 32, width: 960, height: 1008, fullscreen: 0 }
], mon, 32)
assertEqual(saved.windows.length, 2, 'captureLayout records both windows')
assertEqual(saved.windows[0].kind, 'l', 'left half is saved as kind l')
assertEqual(saved.windows[1].kind, 'r', 'right half is saved as kind r')
assertEqual(saved.windows[0].address, '0x1', 'captureLayout stores the compositor address')
const matched = m.matchLayout([
  { address: '0x2', appId: 'foot' },
  { address: '0x1', appId: 'foot' }
], saved)
assertEqual(matched[0].address, '0x1', 'matchLayout prefers the saved address even when list order changes')
assertEqual(matched[0].kind, 'l', 'address 0x1 restores left')
assertEqual(matched[1].address, '0x2', 'second saved address still restores')
assertEqual(matched[1].kind, 'r', 'address 0x2 restores right')

const mixed = m.compositorMonitor({ width: 1920, height: 1080, reserved: [0, 0, 0, 40] })
assertEqual(mixed.height, 1080, 'compositorMonitor keeps the output height, not a gap-subtracted 1054')
const floated = m.defaultFloatRect(mon)
assert(floated.width < 960 && floated.height < 1040, 'default float must not be a work-area half-tile')
const cascaded = m.cascadeRect(mon, 2)
assertEqual(cascaded.width, floated.width, 'cascade keeps the fallback size')
assert(cascaded.x > floated.x, 'cascade offsets later windows')
const clamped = m.clampRect({ x: -40, y: -40, width: 4000, height: 4000 }, mon)
assert(clamped.width <= area.width, 'clamp fits width to the monitor work area')
assert(clamped.x >= area.x, 'clamp keeps x on the monitor')
const offscreenChrome = m.clampRect({ x: 534, y: -479, width: 1252, height: 1000 }, mon)
assert(offscreenChrome.y >= area.y, 'clamp pulls title chrome back onto the work area')
assert(offscreenChrome.x >= area.x, 'clamp keeps a restored float on the monitor x')
const stored = m.parsePlacements(m.serializePlacements({ foot: { x: 48, y: 48, width: 880, height: 560 } }))
assertEqual(stored.foot.width, 880, 'placements round-trip through JSON')
const snapped = { x: 0, y: 0, width: 960, height: 1040 }
assert(m.isSnapped(snapped, mon, 8), '960x1040 at origin is the left snap')
const snappedBar = { x: 0, y: 32, width: 960, height: 1008 }
assert(m.isSnapped(snappedBar, mon, 8, 32), '960x1008 at y=32 is the desktop left snap')
assert(!m.isSnapped(floated, mon, 8), 'default float must not count as snapped')
assert(m.coversWorkArea({ x: 0, y: 0, width: 1920, height: 1040 }, mon), 'full work area is covering')
assert(!m.coversWorkArea(floated, mon), 'default float is not covering')
const mon2 = { x: 1920, y: 0, width: 1920, height: 1080, reserved: [0, 0, 0, 40] }
assertEqual(m.workArea(mon2).x, 1920, 'second monitor work area uses global compositor x')
assertEqual(m.snapRect(mon2, 'l', 32).x, 1920, 'left snap on the right monitor stays on that monitor')
assertDeepEqual(m.desktopIds([{ id: 1, name: '1' }, { id: 2, name: '2' }, { id: -98, name: 'special:scratchpad' }]), [1, 2], 'desktopIds skips special workspaces')
assertEqual(m.neighborDesktop([1, 2, 3], 2, 'l'), 1, 'Win+Ctrl+Left goes to the previous desktop')
assertEqual(m.neighborDesktop([1, 2, 3], 1, 'l'), 1, 'Win+Ctrl+Left does not wrap off the first desktop')
assertEqual(m.nextDesktopId([1, 2]), 3, 'New desktop is max id plus one')
const leftMon = { name: 'Virtual-1', x: 0, y: 0, width: 1920, height: 1080 }
const rightMon = { name: 'HEADLESS-2', x: 1920, y: 0, width: 1920, height: 1080 }
assertEqual(m.neighborMonitor([leftMon, rightMon], leftMon, 'r').name, 'HEADLESS-2', 'Win+Shift+Right picks the monitor to the right')
assertEqual(m.neighborMonitor([leftMon, rightMon], leftMon, 'l'), null, 'Win+Shift+Left does nothing on the leftmost monitor')

const csdJson = fs.readFileSync(path.join(root, 'default/ultimate/csd-clients.json'), 'utf8')
const csd = JSON.parse(csdJson)
assert(Array.isArray(csd.classPatterns) && csd.classPatterns.length > 0, 'csd-clients.json lists classPatterns')
assert(m.csdClassPatterns().length === csd.classPatterns.length, 'WindowModel compiles every JSON CSD pattern')
m.setCsdClientsJson(JSON.stringify({ classPatterns: ['^only-foo$'] }))
assertEqual(m.usesWaylandCsd({ class: 'org.gnome.Nautilus' }), false, 'CSD matching follows the JSON file, not a second list')
assertEqual(m.usesWaylandCsd({ class: 'only-foo' }), true, 'JSON CSD patterns are live')
m.setCsdClientsJson(csdJson)
assertEqual(m.usesWaylandCsd({ class: 'org.gnome.Nautilus' }), true, 'restored JSON still matches Files')
assertEqual(m.usesWaylandCsd({ class: 'zenity' }), false, 'zenity stays off the JSON CSD list')
JS
