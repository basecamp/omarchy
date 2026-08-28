#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const network = requireFromRoot('shell/plugins/panels/network/Model.js')
const panelSource = fs.readFileSync(root + '/shell/plugins/panels/network/Panel.qml', 'utf8')

// --- fuzzyMatchSsid ---

assert(network.fuzzyMatchSsid('Coffee-Shop-Guest', 'cfe'), 'fuzzy match finds an in-order subsequence')
assert(network.fuzzyMatchSsid('Coffee-Shop-Guest', 'COFFEE'), 'fuzzy match is case-insensitive')
assert(!network.fuzzyMatchSsid('Coffee-Shop-Guest', 'efc'), 'fuzzy match requires the query characters in order')
assert(network.fuzzyMatchSsid('Coffee-Shop-Guest', ''), 'an empty query matches every SSID')
assert(!network.fuzzyMatchSsid('', 'x'), 'an empty SSID cannot satisfy a non-empty query')

// --- filterWifiRows ---

const rows = [
  { connected: true, known: true, ssid: 'HomeBase', signal: 90 },
  { connected: false, known: true, ssid: 'Hotspot-Office', signal: 70 },
  { connected: false, known: false, ssid: '', signal: 60 },
  { connected: false, known: false, ssid: 'Neighbor 5G', signal: 40 },
]

const all = network.filterWifiRows(rows, '')
assertEqual(all.length, 4, 'an empty query keeps the whole list, hidden rows included')

const narrowed = network.filterWifiRows(rows, 'ho')
assertEqual(
  narrowed.map(r => r.ssid).join(','),
  'HomeBase,Hotspot-Office,Neighbor 5G',
  'filtering preserves the incoming sort order of the matches'
)

assertEqual(
  network.filterWifiRows(rows, 'off').map(r => r.ssid).join(','),
  'Hotspot-Office',
  'a tighter query narrows down to the single subsequence match'
)

assertEqual(network.filterWifiRows(rows, 'z').length, 0, 'a query with no matches empties the list')
assert(
  network.filterWifiRows(rows, 'e').every(r => r.ssid !== ''),
  'hidden-SSID rows never match a non-empty query'
)

// --- Panel wiring ---

// The query must narrow wifiNetworks itself: selection clamping, section
// titles, and the ListView all read that one list, so filtering anywhere
// else would let the cursor land on rows the eye cannot see.
const syncFn = panelSource.match(/function syncWifiNetworks\(\) \{[\s\S]*?\n {2}\}/)
assert(syncFn, 'network has a syncWifiNetworks function')
assert(/Model\.filterWifiRows\(Model\.sortWifiRows\(nets\), filterText\)/.test(syncFn[0]),
  'syncWifiNetworks applies the fuzzy filter after sorting')

assert(/onFilterTextChanged:[\s\S]*?syncWifiNetworks\(\)/.test(panelSource),
  'typing in the filter re-narrows the list immediately')

// "/" opens the filter; the field then owns the keyboard the same way the
// passphrase prompt does, or j/k would type into the query.
assert(/t === "\/"[\s\S]*?root\.openFilter\(\)/.test(panelSource), 'the "/" key opens the network filter')
assert(/blocked: root\.passwordSsid !== "" \|\| filterField\.activeFocus/.test(panelSource),
  'the key catcher yields to the filter field while it has focus')

// Esc is staged: first back out of the filter, only then close the panel.
const closeReq = panelSource.match(/onCloseRequested: \{[\s\S]*?\n {6}\}/)
assert(closeReq, 'network has a close-request handler')
assert(/cancelFilter\(\)/.test(closeReq[0]) && /else root\.close\(\)/.test(closeReq[0]),
  'Esc clears an active filter before it closes the panel')

// A passphrase prompt reached through the filter must hand focus back to the
// still-visible search field on close, or typing turns into j/k navigation
// under an open editor.
const passwordClose = panelSource.match(/onPasswordSsidChanged: \{[\s\S]*?\n {2}\}/)
assert(passwordClose, 'network has a password-close focus handler')
assert(/filterOpen && filterField\.visible[\s\S]*?filterField\.forceActiveFocus\(\)/.test(passwordClose[0]),
  'closing the passphrase prompt restores focus to an open filter field')

// Outside-click closes skip close(), so reopen must not inherit a stale query.
const openedHandler = panelSource.match(/onOpenedChanged: \{[\s\S]*?refresh\(true\)/)
assert(openedHandler && /cancelFilter\(\)/.test(openedHandler[0]),
  'reopening the panel starts with the filter cleared')
JS
