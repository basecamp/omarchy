#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const network = requireFromRoot('shell/plugins/panels/network/Model.js')
const panelSource = fs.readFileSync(root + '/shell/plugins/panels/network/Panel.qml', 'utf8')

// parseVpnConnections: omarchy-network-vpn prints "name\tactive" lines.
assertDeepEqual(
  network.parseVpnConnections('pvpn-ch\tno\npvpn-fr\tyes\n'),
  [{ name: 'pvpn-ch', active: false }, { name: 'pvpn-fr', active: true }],
  'parseVpnConnections reads name/active pairs'
)

assertDeepEqual(network.parseVpnConnections(''), [], 'parseVpnConnections handles empty output')
assertDeepEqual(network.parseVpnConnections(undefined), [], 'parseVpnConnections handles undefined input')

// sortVpnConnections: active profile first, then alphabetical among the rest --
// mirrors sortWifiRows putting the connected network first.
assertDeepEqual(
  network.sortVpnConnections([
    { name: 'pvpn-fr', active: false },
    { name: 'pvpn-ch', active: true },
    { name: 'pvpn-de', active: false }
  ]),
  [
    { name: 'pvpn-ch', active: true },
    { name: 'pvpn-de', active: false },
    { name: 'pvpn-fr', active: false }
  ],
  'sortVpnConnections puts the active connection first, then sorts by name'
)

// Structural checks against Panel.qml, same style as network-test.sh: catch a
// wiring mistake (poll timer not gated, action not clearing busy state, list
// section still visible with nothing to show) without a running compositor.
assert(/property var vpnConnections: \[\]/.test(panelSource), 'network panel declares vpnConnections')
assert(/property string vpnActionName: ""/.test(panelSource), 'network panel declares vpnActionName')

assert(/if \(!vpnProc\.running\) vpnProc\.running = true/.test(panelSource), 'refresh() kicks off the VPN listing')

const vpnPoll = panelSource.match(/Timer \{\n {4}id: vpnPoll[\s\S]*?\n {2}\}/)
assert(vpnPoll, 'network panel has a vpnPoll timer')
assert(/running: root\.opened/.test(vpnPoll[0]), 'vpnPoll only runs while the panel is open, like bandPoll')

const vpnActionProc = panelSource.match(/Process \{\n {4}id: vpnActionProc[\s\S]*?\n {2}\}/)
assert(vpnActionProc, 'network panel has a vpnActionProc')
assert(/root\.vpnActionName = ""/.test(vpnActionProc[0]), 'vpnActionProc clears the busy row on exit')
assert(
  /root\.vpnWarningName = exitCode === 2 \? root\.vpnActionName : ""/.test(vpnActionProc[0]),
  'vpnActionProc reads exit code 2 as a connected-but-no-traffic warning'
)

assert(/property string vpnWarningName: ""/.test(panelSource), 'network panel declares vpnWarningName')

const toggleVpn = panelSource.match(/function toggleVpn\(name, active\) \{[\s\S]*?\n {2}\}/)
assert(toggleVpn, 'network panel has a toggleVpn function')
assert(/vpnActionProc\.running/.test(toggleVpn[0]), 'toggleVpn guards against overlapping toggles')

assert(/visible: root\.vpnConnections\.length > 0/.test(panelSource), 'VPN section is hidden when there are no profiles')

const vpnRow = panelSource.match(/component VpnRow: CursorSurface \{[\s\S]*?\n {2}\}/)
assert(vpnRow, 'network panel defines a VpnRow row component')
assert(/onClicked: root\.toggleVpn\(row\.conn\.name, row\.isActive\)/.test(vpnRow[0]), 'VpnRow click toggles the connection')
assert(/isWarning: !isBusy && root\.vpnWarningName/.test(vpnRow[0]), 'VpnRow only shows a warning once its own toggle has settled')
assert(/"Connected, no traffic"/.test(vpnRow[0]), 'VpnRow surfaces the no-traffic warning text')
JS
