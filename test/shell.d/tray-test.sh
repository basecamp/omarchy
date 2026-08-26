#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test "tray model helpers" <<'JS'
const tray = requireFromRoot('shell/plugins/bar/widgets/TrayModel.js')

assert(tray.itemNamed({ id: 'dropbox-client' }, 'dropbox'), 'tray matches item ids')
assert(tray.itemNamed({ title: 'Dropbox' }, 'dropbox'), 'tray matches item titles')
assert(tray.itemNamed({ tooltipTitle: 'LocalSend' }, 'localsend'), 'tray matches item tooltips')
assert(!tray.itemNamed({ id: 'nextcloud' }, 'dropbox'), 'tray ignores items named for something else')

const layout = {
  left: [{ id: 'omarchy.menu' }],
  center: [],
  right: [{ id: 'omarchy.dropbox' }, { id: 'omarchy.tray' }]
}

assert(tray.layoutHasWidget(layout, 'omarchy.dropbox'), 'tray finds dedicated dropbox widget in layout')
assert(tray.ownedByOmarchy({ id: 'dropbox' }, layout), 'tray suppresses dropbox when dedicated widget is in bar')
assert(!tray.ownedByOmarchy({ id: 'dropbox' }, { left: [], center: [], right: [] }), 'tray keeps dropbox when dedicated widget is absent')
assert(tray.ownedByOmarchy({ id: 'qlBCprNUqU', title: 'localsend' }, { left: [], center: [], right: [] }), 'tray suppresses localsend regardless of layout')
assert(!tray.ownedByOmarchy({ id: 'nextcloud' }, layout), 'tray keeps unrelated tray items')

const empty = { pinnedIds: [], hiddenIds: [], unpinnedIds: [], pinNew: false }
assert(tray.classifyItem({ id: 'steam' }, empty) === 'drawer', 'unknown items go in the drawer by default')
assert(tray.classifyItem({ id: 'steam' }, { ...empty, pinNew: true }) === 'pinned', 'pinNew shows unknown items')
assert(tray.classifyItem({ id: 'steam' }, { ...empty, hiddenIds: ['steam'], pinNew: true }) === 'hidden', 'hidden wins over pinNew')
assert(tray.classifyItem({ id: 'steam' }, { ...empty, unpinnedIds: ['steam'], pinNew: true }) === 'drawer', 'explicit unpin stays in the drawer when pinNew is on')
assert(tray.classifyItem({ id: 'steam' }, { ...empty, pinnedIds: ['steam'] }) === 'pinned', 'pinned items stay visible with pinNew off')

const pinned = tray.togglePin('steam', [], [], [], true)
assertDeepEqual(pinned.unpinned, ['steam'], 'unpinning a pinNew item records it as unpinned')
assertDeepEqual(pinned.pinned, [], 'unpinning a pinNew item does not leave it in pinned')
assert(tray.classifyItem({ id: 'steam' }, { pinnedIds: pinned.pinned, hiddenIds: pinned.hidden, unpinnedIds: pinned.unpinned, pinNew: true }) === 'drawer', 'unpin still works when pinNew is on')

const repinned = tray.togglePin('steam', pinned.pinned, pinned.unpinned, pinned.hidden, true)
assertDeepEqual(repinned.pinned, ['steam'], 'pinning an unpinned item adds it to pinned')
assertDeepEqual(repinned.unpinned, [], 'pinning an unpinned item clears unpinned')

const hidden = tray.toggleHide('steam', ['steam'], [], [])
assertDeepEqual(hidden.hidden, ['steam'], 'hide records the item as hidden')
assertDeepEqual(hidden.pinned, [], 'hide removes the item from pinned')
assert(tray.classifyItem({ id: 'steam' }, { pinnedIds: hidden.pinned, hiddenIds: hidden.hidden, unpinnedIds: hidden.unpinned, pinNew: true }) === 'hidden', 'hidden still hides when pinNew is on')
JS
