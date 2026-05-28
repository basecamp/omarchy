#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

if perl -0ne 'exit(/drag\s*\.\s*target\s*:\s*[^;]*\bslot\b/s ? 0 : 1)' "$ROOT/shell/plugins/bar/Bar.qml"; then
  fail "bar module dragging must not mutate ModuleSlot positions"
fi
pass "bar module dragging leaves layout-managed slots in place"

run_node_test <<'JS'
const bar = requireFromRoot('shell/plugins/bar/BarModel.js')

assertEqual(bar.normalizePosition('left'), 'left', 'bar accepts valid positions')
assertEqual(bar.normalizePosition('sideways'), 'top', 'bar defaults invalid positions')
assertDeepEqual(bar.entrySettings({ id: 'omarchy.clock', format: 'HH:mm' }), { format: 'HH:mm' }, 'bar extracts entry settings')
assertEqual(bar.entryId({ id: 'omarchy.clock' }), 'omarchy.clock', 'bar extracts object entry ids')
assertEqual(bar.entryId('omarchy.clock'), 'omarchy.clock', 'bar extracts string entry ids')

const entries = [{ id: 'a' }, { id: 'omarchy.tray' }, { id: 'b' }]
assertDeepEqual(bar.pinTrayToInner(entries, 'left').map(bar.entryId), ['a', 'b', 'omarchy.tray'], 'bar pins tray to left inner edge')
assertDeepEqual(bar.pinTrayToInner(entries, 'right').map(bar.entryId), ['omarchy.tray', 'a', 'b'], 'bar pins tray to right inner edge')

assertEqual(bar.moduleString({ id: 'custom', label: 42 }, 'label', 'fallback'), '42', 'bar stringifies module settings')
assertEqual(bar.entryIndex(entries, 'b'), 2, 'bar finds entry indexes')
assertDeepEqual(bar.entriesBefore(entries, 'b').map(bar.entryId), ['a', 'omarchy.tray'], 'bar returns entries before target')
assertDeepEqual(bar.entriesAfter(entries, 'a').map(bar.entryId), ['omarchy.tray', 'b'], 'bar returns entries after target')

assertEqual(bar.expandPath('~/module.qml', '/home/dhh'), '/home/dhh/module.qml', 'bar expands tilde paths')
assertEqual(bar.expandPath('$HOME/module.qml', '/home/dhh'), '/home/dhh/module.qml', 'bar expands HOME paths')
assert(bar.customModuleSafeName('local.weather'), 'bar accepts safe custom module names')
assert(!bar.customModuleSafeName('../escape'), 'bar rejects path traversal custom module names')
assertEqual(bar.customModuleType({ id: 'custom', exec: 'date' }), 'command', 'bar infers command custom modules')
assertEqual(bar.customModuleType({ id: 'custom', source: '~/Custom.qml' }), 'qml', 'bar infers qml custom modules')
assertEqual(
  bar.customModulePath({ id: 'local.weather' }, '/home/dhh', '/home/dhh/.config/omarchy'),
  '/home/dhh/.config/omarchy/bar/modules/local.weather.qml',
  'bar builds default custom module paths'
)
JS
