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
JS

run_node_test "tray drawer capture, order, and drag-out" <<'JS'
const tray = requireFromRoot('shell/plugins/bar/widgets/TrayModel.js')

function config() {
  return {
    bar: { layout: {
      left: [],
      center: [{ id: 'omarchy.weather' }],
      right: [{ id: 'omarchy.tray' }, { id: 'omarchy.bluetooth' }]
    } },
    plugins: []
  }
}

// Capturing pulls the entry out of the layout, wraps it, and applies the
// drop-position order the caller computed.
let c = config()
assert(tray.captureIntoTray(c, 'omarchy.tray', 'omarchy.weather', ['omarchy.weather', 'icon-1']), 'capture moves a layout entry into the tray')
assert(c.bar.layout.center.length === 0, 'captured entry leaves its section')
const entry = c.bar.layout.right[0]
assert(entry.widgets.length === 1 && entry.widgets[0].entry.id === 'omarchy.weather', 'tray holds the captured wrapper')
assert(entry.order.join(',') === 'omarchy.weather,icon-1', 'capture applies the drop-position order')
assert(!tray.captureIntoTray(c, 'omarchy.tray', 'omarchy.tray', null), 'the tray cannot capture itself')

// Third-party widgets stay loaded via a plugins[] listing, removed again on
// the way out; entries that were already listed are left alone.
c = config()
c.bar.layout.center.push({ id: 'acme.widget' })
assert(tray.captureIntoTray(c, 'omarchy.tray', 'acme.widget', null), 'captures a third-party widget')
assert(c.plugins.some(p => p.id === 'acme.widget'), 'capture lists the plugin so its component stays loaded')
assert(tray.dragOutOfTray(c, 'omarchy.tray', 'acme.widget', 'right', 'omarchy.bluetooth'), 'drag-out returns the widget to the layout')
assert(!c.plugins.some(p => p.id === 'acme.widget'), 'drag-out unlists what capture listed')
assert(c.bar.layout.right.map(e => e.id).join(',') === 'omarchy.tray,acme.widget,omarchy.bluetooth', 'drag-out inserts before the named entry')

// Order helpers: stable sort by token list with unknowns last, and
// no-op-aware reordering.
const items = [{ id: 'b' }, { id: 'a' }, { id: 'new' }]
assert(tray.sortByOrder(items, ['a', 'b']).map(i => i.id).join(',') === 'a,b,new', 'sortByOrder applies the token list, unknowns last')
assert(tray.movedBefore(['a', 'b', 'c'], 'c', 'a').join(',') === 'c,a,b', 'movedBefore inserts ahead of the target')
assert(tray.movedBefore(['a', 'b'], 'b', '') === null, 'movedBefore reports no-ops as null')

// Settings arrays can arrive as array-like proxies from QML; asList copies
// anything list-shaped into a real array.
const proxy = { length: 2, 0: 'x', 1: 'y' }
assert(tray.asList(proxy).join(',') === 'x,y', 'asList unwraps array-like proxies')
assert(tray.asList(null).length === 0, 'asList tolerates junk')
JS
