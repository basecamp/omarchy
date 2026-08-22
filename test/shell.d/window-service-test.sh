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

grep -Fq 'setfloating' "$ws" || fail "snap uses setfloating instead of toggling tile state"
if grep -A20 'function _snapActive' "$ws" | grep -Fq 'togglefloating'; then
  fail "snap must not togglefloating an already-floating window"
fi
pass "snap uses setfloating rather than togglefloating"

grep -Fq 'function cycleNext' "$ws" || fail "WindowService exposes cycleNext for Alt+Tab"
grep -Fq 'function commitCycle' "$ws" || fail "WindowService exposes commitCycle for Alt release"
grep -Fq 'function toggleShowDesktop' "$ws" || fail "WindowService exposes toggleShowDesktop"
grep -Fq 'function pin' "$ws" || fail "WindowService exposes pin for the taskbar"
pass "WindowService exposes task-switcher, Show Desktop, and pin verbs"

grep -Fq 'target: "window"' "$ROOT/shell/shell.qml" || fail "shell registers a window IPC target"
grep -Fq 'function pin' "$ROOT/shell/shell.qml" || fail "window IPC exposes pin"
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
