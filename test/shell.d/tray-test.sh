#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test "tray model helpers" <<'JS'
const tray = requireFromRoot('shell/plugins/bar/widgets/TrayModel.js')

assert(tray.isDropboxTrayItem({ id: 'dropbox-client' }), 'tray detects dropbox item ids')
assert(tray.isDropboxTrayItem({ title: 'Dropbox' }), 'tray detects dropbox item titles')
assert(!tray.isDropboxTrayItem({ id: 'nextcloud' }), 'tray ignores non-dropbox items')

const layout = {
  left: [{ id: 'omarchy.menu' }],
  center: [],
  right: [{ id: 'omarchy.dropbox' }, { id: 'omarchy.tray' }]
}

assert(tray.layoutHasWidget(layout, 'omarchy.dropbox'), 'tray finds dedicated dropbox widget in layout')
assert(tray.ownedByDedicatedWidget({ id: 'dropbox' }, layout), 'tray suppresses dropbox when dedicated widget is in bar')
assert(!tray.ownedByDedicatedWidget({ id: 'dropbox' }, { left: [], center: [], right: [] }), 'tray keeps dropbox when dedicated widget is absent')
assert(!tray.ownedByDedicatedWidget({ id: 'nextcloud' }, layout), 'tray keeps unrelated tray items')
JS
