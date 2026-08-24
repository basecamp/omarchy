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
assert(/property string vpnActionKind: ""/.test(panelSource), 'network panel declares vpnActionKind')
assert(/property string vpnFailureName: ""/.test(panelSource), 'network panel declares vpnFailureName')
assert(/property string vpnFailureReason: ""/.test(panelSource), 'network panel declares vpnFailureReason')

assert(/if \(!vpnProc\.running\) vpnProc\.running = true/.test(panelSource), 'refresh() kicks off the VPN listing')

const vpnPoll = panelSource.match(/Timer \{\n {4}id: vpnPoll[\s\S]*?\n {2}\}/)
assert(vpnPoll, 'network panel has a vpnPoll timer')
assert(/running: root\.opened/.test(vpnPoll[0]), 'vpnPoll only runs while the panel is open, like bandPoll')

const updateVpnConnections = panelSource.match(/function updateVpnConnections\(raw\) \{[\s\S]*?\n {2}\}/)
assert(updateVpnConnections, 'network panel has an updateVpnConnections function')
assert(
  /if \(!stillActive\) vpnFailureName = ""/.test(updateVpnConnections[0]),
  'updateVpnConnections drops a failure once its connection is no longer active'
)

const vpnActionProc = panelSource.match(/Process \{\n {4}id: vpnActionProc[\s\S]*?\n {2}\}/)
assert(vpnActionProc, 'network panel has a vpnActionProc')
assert(/root\.vpnActionName = ""/.test(vpnActionProc[0]), 'vpnActionProc clears the busy row on exit')
assert(/root\.vpnActionKind = ""/.test(vpnActionProc[0]), 'vpnActionProc clears the pending action kind on exit')
assert(/exitCode === 0/.test(vpnActionProc[0]), 'vpnActionProc treats exit 0 as a plain success')
assert(
  /exitCode === 75\s*\n\s*\? "Connected, no traffic"/.test(vpnActionProc[0]),
  'vpnActionProc reads the private exit code 75 as a connected-but-no-traffic warning, not nmcli\'s own exit 2'
)
assert(
  /root\.vpnActionKind === "down" \? "Failed to disconnect" : "Failed to connect"/.test(vpnActionProc[0]),
  'vpnActionProc surfaces a plain nmcli failure distinctly from the no-traffic case'
)

const toggleVpn = panelSource.match(/function toggleVpn\(name, active\) \{[\s\S]*?\n {2}\}/)
assert(toggleVpn, 'network panel has a toggleVpn function')
assert(/vpnActionProc\.running/.test(toggleVpn[0]), 'toggleVpn guards against overlapping toggles')
assert(/vpnActionKind = active \? "down" : "up"/.test(toggleVpn[0]), 'toggleVpn records which direction it requested')

assert(/visible: root\.vpnConnections\.length > 0/.test(panelSource), 'VPN section is hidden when there are no profiles')

const vpnRow = panelSource.match(/component VpnRow: CursorSurface \{[\s\S]*?\n {2}\}/)
assert(vpnRow, 'network panel defines a VpnRow row component')
assert(/onClicked: root\.toggleVpn\(row\.conn\.name, row\.isActive\)/.test(vpnRow[0]), 'VpnRow click toggles the connection')
assert(/isFailed: !isBusy && root\.vpnFailureName/.test(vpnRow[0]), 'VpnRow only shows a failure once its own toggle has settled')
assert(/root\.vpnFailureReason/.test(vpnRow[0]), 'VpnRow renders the failure reason the panel recorded')

// Keyboard navigation: PanelKeyCatcher maps both arrow keys and j/k/h/l to
// the same onMoveRequested(dx, dy), so wiring the "vpn" section into that
// one handler covers both input styles at once -- nothing arrow-specific to
// test separately.
assert(/property int vpnIndex: -1/.test(panelSource), 'network panel declares vpnIndex')
assert(/"header" \| "band" \| "dns" \| "vpn" \| "wifi"/.test(panelSource), 'focusSection docs list vpn between dns and wifi')

const moveHandler = panelSource.match(/onMoveRequested: function\(dx, dy\) \{[\s\S]*?\n {6}\}\n {4}\}/)
assert(moveHandler, 'network panel has the onMoveRequested handler')
assert(
  /root\.focusSection === "dns"[\s\S]*?root\.vpnConnections\.length > 0\)[\s\S]*?root\.focusSection = "vpn"/.test(moveHandler[0]),
  'j from DNS enters the VPN section when it has profiles'
)
assert(
  /root\.focusSection === "vpn"[\s\S]*?dy < 0 && root\.vpnIndex <= 0[\s\S]*?root\.focusSection = "dns"/.test(moveHandler[0]),
  'k from the top VPN row escapes back to DNS'
)
assert(
  /root\.focusSection === "vpn"[\s\S]*?dy > 0 && root\.vpnIndex >= root\.vpnConnections\.length - 1[\s\S]*?root\.focusSection = "wifi"/.test(moveHandler[0]),
  'j from the bottom VPN row drops into wifi when there is somewhere to land'
)
assert(
  /root\.selectedIndex <= 0\)[\s\S]*?root\.vpnConnections\.length > 0\)[\s\S]*?root\.focusSection = "vpn"/.test(moveHandler[0]),
  'k from the top wifi row returns to VPN when it has profiles'
)

const activateHandler = panelSource.match(/onActivateRequested: \{[\s\S]*?\n {6}\}\n {4}\}/)
assert(activateHandler, 'network panel has the onActivateRequested handler')
assert(/root\.focusSection === "vpn"\) root\.activateVpn\(\)/.test(activateHandler[0]), 'Enter/Space on the VPN section activates the selected row')

const activateVpn = panelSource.match(/function activateVpn\(\) \{[\s\S]*?\n {2}\}/)
assert(activateVpn, 'network panel has an activateVpn function')
assert(/toggleVpn\(conn\.name, conn\.active\)/.test(activateVpn[0]), 'activateVpn toggles the row under the keyboard cursor')

assert(/isSelected: root\.focusSection === "vpn" && root\.vpnIndex === index/.test(vpnRow[0]), 'VpnRow tracks whether it is the keyboard-selected row')
assert(/hasCursor: root\.cursorActive && isSelected/.test(vpnRow[0]), 'VpnRow shows the keyboard cursor, not just mouse hover')
assert(
  /enabled: root\.vpnActionName === ""/.test(vpnRow[0]),
  'VpnRow locks every row while any VPN toggle is in flight, not just its own'
)

// The VPN list is a capped, scrollable ListView (like networkList below it),
// not an unbounded Column -- a long profile list must scroll instead of
// pushing DNS/wifi off the card.
const vpnListView = panelSource.match(/ListView \{\n {10}id: vpnList[\s\S]*?\n {8}\}/)
assert(vpnListView, 'network panel has a capped vpnList ListView')
assert(/height: Math\.min\(contentHeight, Style\.space\(240\)\)/.test(vpnListView[0]), 'vpnList caps its height like networkList')
assert(/clip: true/.test(vpnListView[0]), 'vpnList clips overflow instead of pushing later sections off the card')
assert(/currentIndex: root\.vpnIndex/.test(vpnListView[0]), 'vpnList follows the keyboard cursor')
assert(/positionViewAtIndex\(currentIndex, ListView\.Contain\)/.test(vpnListView[0]), 'vpnList scrolls the keyboard-selected row into view')

// A long connection name must not run under the status text on its right.
assert(/elide: Text\.ElideRight/.test(vpnRow[0]), 'VpnRow elides a name too long to fit')
assert(/anchors\.right: statusText\.left/.test(vpnRow[0]), 'VpnRow name is width-constrained against the status text, not free to overlap it')
JS
