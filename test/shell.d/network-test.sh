#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const network = requireFromRoot('shell/plugins/panels/network/Model.js')
const panelSource = fs.readFileSync(root + '/shell/plugins/panels/network/Panel.qml', 'utf8')

assert(/IpcHandler[\s\S]*?function toggleNetwork\(\) \{ root\.toggleNetwork\(\) \}/.test(panelSource), 'network exposes the Wi-Fi radio toggle over IPC')
assert(/manageIpc: false/.test(panelSource), 'network owns its IPC handler so it can extend the target methods')

// Opening from the bar must call open() and nothing else. open() runs
// refresh(true), which defers the PHY scan; a second bare refresh() defaults
// scanWifi to false, sets scannerEnabled synchronously, and stalls the open on
// NetworkManager's access-point flood.
const barPress = panelSource.match(/onPressed: function\(b\) \{[\s\S]*?\n {4}\}/)
assert(barPress, 'network bar button has an onPressed handler')
const barPressCode = barPress[0].replace(/\/\/.*$/gm, '')
assert(!/refresh\(/.test(barPressCode), 'network bar click opens the panel without a second refresh that would undo the deferred scan')

// A closed panel has no nearby-network list to fill. Quickshell's scanner
// re-arms RequestScan on its own timer, and every sweep takes the radio off
// the operating channel, so a scanner left enabled behind a closed panel keeps
// degrading the connection it is scanning from.
const refreshFn = panelSource.match(/function refresh\(scanWifi\)[\s\S]*?\n {2}\}/)
assert(refreshFn, 'network has a refresh() function')
assert(/if \(opened && wifiDevice\)/.test(refreshFn[0]), 'network only touches the scanner from refresh() while its panel is open')

// The 100ms deferral can outlive the panel: closing inside the window would
// otherwise re-enable scanning from a timer nobody is watching.
const scanRestart = panelSource.match(/id: scanRestart[\s\S]*?onTriggered: \{[\s\S]*?\n {4}\}/)
assert(scanRestart, 'network has the deferred scan restart timer')
assert(/root\.opened/.test(scanRestart[0]), 'network re-checks the panel before the deferred restart re-enables scanning')
assert(/scanRestart\.stop\(\)/.test(panelSource), 'network cancels a pending scan restart when the panel closes')

// scannerEnabled lives on a shared WifiDevice with no reference counting, so
// the panel has to own what it enabled. Run the helper's own JavaScript against
// stand-in devices: the two invariants it carries are that a closed panel never
// takes a device, and that adopting a new one releases the previous.
const scannerHelper = panelSource.match(/function setScannerEnabled\(enabled\) \{[\s\S]*?\n {2}\}/)
assert(scannerHelper, 'network has a scanner ownership helper')

var opened = false
var wifiDevice = { scannerEnabled: false }
var scannerDevice = null
eval(scannerHelper[0])

setScannerEnabled(true)
assert(
  scannerDevice === null && wifiDevice.scannerEnabled === false,
  'network does not let a closed panel claim or enable a scanner device'
)

var previousScannerDevice = { scannerEnabled: true }
var replacementScannerDevice = { scannerEnabled: false }
opened = true
scannerDevice = previousScannerDevice
wifiDevice = replacementScannerDevice
setScannerEnabled(true)
assert(
  previousScannerDevice.scannerEnabled === false &&
    scannerDevice === replacementScannerDevice &&
    replacementScannerDevice.scannerEnabled === true,
  'network releases the previous scanner device before enabling its replacement'
)

// Destruction is the case a guard-only fix misses: the widget dies with the
// panel still open, as a bar reload does, and nothing else would release it.
assert(
  /Component\.onDestruction[\s\S]{0,140}scannerDevice\.scannerEnabled = false/.test(panelSource),
  'network releases the scanner it owns when the widget is destroyed'
)
assert(!/wifiDevice\.scannerEnabled\s*=/.test(panelSource), 'network writes scanner state through its owned device reference rather than the moving wifiDevice reference')

// A row is a primitive snapshot that can outlive its WifiNetwork, and
// disconnect() falls back to the live connection when handed null, so row
// activation must go through the guarded disconnectRow().
assert(
  /function disconnectRow\(ssid\) \{\s*var network = networkForSsid\(ssid\)\s*if \(network\) disconnect\(network\)/.test(panelSource),
  'network guards row disconnects so a stale row cannot drop an unrelated connection'
)
assert(!/disconnect\(\s*(root\.)?networkForSsid\(/.test(panelSource), 'network never passes an unguarded networkForSsid() lookup to disconnect()')

assertDeepEqual(
  network.parseNetworkStatus('wifi\tCafe WiFi\t78\t5200\n'),
  { kind: 'wifi', label: 'Cafe WiFi', signalStrength: 78, frequency: '5200' },
  'network parses bar status'
)
assertEqual(network.connectionIcon('wifi', 80), network.wifiIconFor(80), 'network maps wifi icon from signal')
assertEqual(network.formatHeaderSpeed('1000'), '1gbit', 'network formats gigabit speed')
assertEqual(network.formatHeaderSpeed('2500'), '2.5gbit', 'network formats fractional gigabit speed')
assertEqual(network.formatHeaderFreq('2462'), '2.4ghz', 'network formats 2.4GHz wifi band')
assertEqual(network.formatHeaderFreq('5200'), '5ghz', 'network formats 5GHz wifi band')
assertEqual(network.formatHeaderFreq('6455.0'), '6ghz', 'network formats 6GHz wifi band')
assertEqual(network.formatHeaderFreq('18300'), '18.3ghz', 'network falls back to exact GHz for unknown bands')
assertEqual(network.headerDetail({ type: 'ethernet', speed: '100' }), '100mbit', 'network header uses ethernet speed')

assertDeepEqual(
  network.parseKeyValue('iface\twlan0\nrx_bytes\t100\ntx_bytes\t50\n'),
  { iface: 'wlan0', rx_bytes: '100', tx_bytes: '50' },
  'network parses detail key values'
)
assertEqual(network.decodeIwSsid('Cafe\\xe2\\x80\\x99'), 'Cafe’', 'network decodes UTF-8 SSID bytes')
assertEqual(network.decodeIwSsid('Smile \\xf0\\x9f\\x98\\x80'), 'Smile 😀', 'network decodes emoji SSID bytes')
assertEqual(network.decodeIwSsid('\\x20Cafe\\x20'), ' Cafe ', 'network preserves edge spaces in SSIDs')
assertEqual(network.decodeIwSsid('slash\\x5cname'), 'slash\\name', 'network decodes SSID backslashes once')
assertEqual(network.decodeIwSsid('invalid\\xff'), 'invalid\\xff', 'network preserves invalid UTF-8 escapes')
assertEqual(network.decodeIwSsid('already 😀'), 'already 😀', 'network safely preserves unexpected non-BMP input')
assertDeepEqual(
  network.parseKeyValue('ssid\tline\\x0abreak\\x09tab\\x00nul\nsignal_dbm\t-40\n'),
  { ssid: 'line\\x0abreak\\x09tab\\x00nul', signal_dbm: '-40' },
  'network leaves control-byte escapes safe for single-line display'
)
assertDeepEqual(
  network.throughputState({ prevIface: '', prevSampleTime: 0 }, { iface: 'wlan0', rx_bytes: '100', tx_bytes: '50' }, 10),
  { prevIface: 'wlan0', prevRxBytes: 100, prevTxBytes: 50, prevSampleTime: 10, downloadRate: 0, uploadRate: 0 },
  'network seeds throughput state on first sample'
)
assertDeepEqual(
  network.throughputState({ prevIface: 'wlan0', prevRxBytes: 100, prevTxBytes: 50, prevSampleTime: 10 }, { iface: 'wlan0', rx_bytes: '300', tx_bytes: '90' }, 12),
  { prevIface: 'wlan0', prevRxBytes: 300, prevTxBytes: 90, prevSampleTime: 12, downloadRate: 100, uploadRate: 20 },
  'network computes throughput deltas'
)

let ping = network.pingLatencyState(
  { pingIface: '', routerPingSamples: [], internetPingSamples: [] },
  { iface: 'wlan0', router_ping_ms: '2.0', internet_ping_ms: '20.0' },
  4
)
assertDeepEqual(
  ping,
  { pingIface: 'wlan0', routerPingSamples: [2], internetPingSamples: [20], routerPingLatency: 2, internetPingLatency: 20, internetPingPacketLoss: 0 },
  'network seeds ping latency samples'
)

ping = network.pingLatencyState(ping, { iface: 'wlan0', router_ping_ms: '4.0', internet_ping_ms: '' }, 4)
assertDeepEqual(
  ping,
  { pingIface: 'wlan0', routerPingSamples: [2, 4], internetPingSamples: [20, null], routerPingLatency: 3, internetPingLatency: 20, internetPingPacketLoss: 50 },
  'network averages recent successful ping samples'
)

assertDeepEqual(
  network.pingLatencyState(ping, { iface: 'eth0', router_ping_ms: '1.5', internet_ping_ms: '10.0' }, 4),
  { pingIface: 'eth0', routerPingSamples: [1.5], internetPingSamples: [10], routerPingLatency: 1.5, internetPingLatency: 10, internetPingPacketLoss: 0 },
  'network resets ping samples when interface changes'
)

assertDeepEqual(
  network.pingLatencyState(ping, { iface: 'wlan0', internet_ping_ms: '22.0' }, 4),
  { pingIface: 'wlan0', routerPingSamples: [], internetPingSamples: [20, null, 22], routerPingLatency: -1, internetPingLatency: 21, internetPingPacketLoss: 33 },
  'network clears ping samples when a target is unavailable'
)

assertEqual(network.formatBytes(1536), '1.5 KB', 'network formats bytes')
assertEqual(network.formatRate(1536), '1.5 KB/s', 'network formats rates')
assertEqual(network.formatPingLatency('2.54'), '2.5 ms', 'network formats low ping with precision')
assertEqual(network.formatPingLatency('25.4'), '25 ms', 'network formats ping')
assertEqual(network.formatPingLatency(''), 'Timeout', 'network formats missing ping as timeout')
assertEqual(network.formatPingLatency(-1, false), '--', 'network holds the ping row before the first sample')
assertEqual(network.formatPingLatency('25.4', true), '25 ms', 'network formats ping once samples exist')
assertEqual(network.formatPingLatency('', true), 'Timeout', 'network still reports a timeout among real samples')
assertEqual(network.formatPacketLoss(2), '2%', 'network formats packet loss')
assertEqual(network.formatPacketLoss(0), '0%', 'network formats zero packet loss')
assertEqual(network.formatPacketLoss(0, false), '--', 'network holds the packet loss row before the first sample')
assertEqual(network.formatPacketLoss(0, true), '0%', 'network reports zero loss once samples exist')

const rows = network.sortWifiRows([
  { ssid: 'Open', connected: false, known: false, signal: 95 },
  { ssid: 'Known', connected: false, known: true, signal: 10 },
  { ssid: 'Connected', connected: true, known: true, signal: 20 }
])
assertDeepEqual(rows.map(row => row.ssid), ['Connected', 'Known', 'Open'], 'network sorts wifi rows by connection and known state')
assertEqual(network.wifiSectionTitle(rows, 0), 'KNOWN NETWORKS', 'network labels known wifi section')
assertEqual(network.wifiSectionTitle(rows, 2), 'OTHER NETWORKS', 'network labels other wifi section')

const wifiRow = network.wifiRow({ connected: true, known: true, name: 'Home', signalStrength: 0.8, security: 1 })
assertDeepEqual(
  wifiRow,
  { connected: true, known: true, ssid: 'Home', signal: 80, security: 1 },
  'network projects wifi rows with primitives so delegates never hold the live WifiNetwork object'
)
assertDeepEqual(
  Object.keys(wifiRow).sort(),
  ['connected', 'known', 'security', 'signal', 'ssid'],
  'network wifi rows project exactly the primitive fields, so each delegate stores no live QObject'
)

const security = {
  Wpa3SuiteB192: 0,
  Sae: 1,
  Wpa2Eap: 2,
  Wpa2Psk: 3,
  WpaEap: 4,
  WpaPsk: 5,
  StaticWep: 6,
  DynamicWep: 7,
  Leap: 8,
  Owe: 9,
  Open: 10,
  Unknown: 11
}
for (const name of ['Wpa3SuiteB192', 'Sae', 'Wpa2Eap', 'Wpa2Psk', 'WpaEap', 'WpaPsk', 'StaticWep', 'DynamicWep', 'Leap', 'Unknown']) {
  assertEqual(network.requiresCredentials(security[name], security.Open, security.Owe), true, 'network asks for ' + name + ' credentials')
}
assertEqual(network.requiresCredentials(security.Owe, security.Open, security.Owe), false, 'network does not ask for OWE credentials')
assertEqual(network.requiresCredentials(security.Open, security.Open, security.Owe), false, 'network does not ask for open-network credentials')

assert(
  /Model\.requiresCredentials\(security, WifiSecurityType\.Open, WifiSecurityType\.Owe\)/.test(panelSource),
  'network wires the Quickshell OWE enum into credential detection'
)
assert(
  /if \(requiresCredentials\(net\.security\) && !net\.known\)/.test(panelSource),
  'network keyboard activation gates unknown-network prompts on credential requirements'
)
assert(
  /if \(row\.requiresCredentials && !row\.isKnown\)/.test(panelSource),
  'network row clicks gate unknown-network prompts on credential requirements'
)
assert(
  /shouldRepromptPassphrase\(reason, row\.requiresCredentials\)/.test(panelSource),
  'network failure reprompts use the row credential requirement'
)
assert(
  /networkFailureReason\(reason, requiresCredentials\(network\.security\)\)/.test(panelSource),
  'network failure copy uses the live network credential requirement'
)

// A connection or known-state change re-sorts the projected rows. Preserve
// the selected SSID through that sort so a focused X never jumps to another
// saved network at the same numeric index.
const syncWifiNetworksFunction = panelSource.match(/function syncWifiNetworks\(\) \{[\s\S]*?\n {2}\}/)
assert(syncWifiNetworksFunction, 'network has a Wi-Fi row synchronization helper')
var Model = network
var wifiNetworks = [
  { connected: true, known: true, ssid: 'Alpha', signal: 50, security: security.Open },
  { connected: false, known: true, ssid: 'Beta', signal: 90, security: security.Open }
]
var wifiNetworkObjects = [
  { connected: false, known: true, name: 'Alpha', signalStrength: 0.5, security: security.Open },
  { connected: false, known: true, name: 'Beta', signalStrength: 0.9, security: security.Open }
]
var selectedIndex = 0
var focusSection = 'wifi'
var wifiActionFocused = true
var wifiDevice = {}
var wifiStationAvailable = false
var scanning = true
function checkActionCompletion() {}
eval(syncWifiNetworksFunction[0])
syncWifiNetworks()
assertEqual(wifiNetworks[selectedIndex].ssid, 'Alpha', 'network selection follows the SSID when rows re-sort')

wifiNetworkObjects = [wifiNetworkObjects[1]]
syncWifiNetworks()
assertEqual(wifiActionFocused, false, 'network clears X focus when the selected SSID disappears')

assert(
  /readonly property bool canForget: root\.canForgetNetwork\(net\)/.test(panelSource),
  'network rows derive forget eligibility from the tested model helper'
)
const networkRowStart = panelSource.indexOf('component NetworkRow: CursorSurface {')
const detailValueStart = panelSource.indexOf('component DetailValue: InfoValue {')
assert(networkRowStart >= 0 && detailValueStart > networkRowStart, 'network exposes its Wi-Fi row component')
const networkRow = panelSource.slice(networkRowStart, detailValueStart)

const rightAction = panelSource.match(/Item \{\s*id: rightAction\b[\s\S]*?\n {6}\}/)
assert(rightAction, 'network has a right-edge action target')
assert(
  /visible: row\.requiresCredentials \|\| row\.actionVisible/.test(rightAction[0]),
  'network keeps the right edge available for locks and revealed row actions'
)
const lockIndicator = networkRow.match(/Text \{\s*id: lockIndicator\b[\s\S]*?\n {8}\}/)
assert(lockIndicator, 'network has a lock indicator')
assert(
  /visible: row\.requiresCredentials && !row\.actionVisible/.test(lockIndicator[0]),
  'network replaces a secured row lock while its trailing action is revealed'
)
assert(
  /readonly property bool actionVisible: \(isConnected \|\| canForget\) && \(rowMouse\.containsMouse \|\| rowSelected\)/.test(networkRow),
  'network reveals a trailing X for connected and saved rows on hover or keyboard focus'
)
assert(
  /readonly property string actionTooltip:[\s\S]{0,220}isConnected[\s\S]{0,220}"Disconnect"/.test(networkRow) &&
    /PanelToolTip \{[\s\S]*?rowMouse\.containsMouse[\s\S]*?text: row\.actionTooltip/.test(networkRow),
  'network shows the row Disconnect tooltip while a connected row is hovered'
)
assert(
  /(?:iconText|text):[^\n]*"󰅙"/.test(networkRow) &&
    /(?:root\.)?forget\(row\.net\)/.test(networkRow),
  'network trailing X invokes Forget for connected and saved rows'
)
assert(
  /if \(row\.isConnected\) \{\s*root\.disconnectRow\(row\.net\.ssid\)/.test(networkRow),
  'network row click disconnects a connected row'
)

// Right/Left navigation must expose the X for a connected row as well as the
// existing Forget action. Execute the real helper body against a connected
// row so this fails if navigation still gates solely on canForgetNetwork().
const selectWifiAction = panelSource.match(/function selectWifiActionByDelta\(delta\) \{[\s\S]*?\n {2}\}/)
assert(selectWifiAction, 'network has horizontal Wi-Fi action navigation')
selectedIndex = 0
var wifiNetworks = [{ connected: true, known: true, security: security.Open }]
var wifiActionFocused = false
function canForgetNetwork(net) { return network.canForgetNetwork(net) }
eval(selectWifiAction[0])
selectWifiActionByDelta(1)
assertEqual(wifiActionFocused, true, 'network Right focuses the X on a connected row')
selectWifiActionByDelta(-1)
assertEqual(wifiActionFocused, false, 'network Left returns from a focused row action')
wifiNetworks = [{ connected: false, known: false, security: security.Open }]
wifiActionFocused = false
selectWifiActionByDelta(1)
assertEqual(wifiActionFocused, false, 'network unknown rows have no trailing X action')

const activateSelectedFunction = panelSource.match(/function activateSelected\(\) \{[\s\S]*?\n {2}\}/)
assert(activateSelectedFunction, 'network has keyboard activation for the selected Wi-Fi row')
var busy = false
wifiActionFocused = false
wifiNetworks = [{ connected: true, known: true, ssid: 'Home', security: security.Open }]
var actionCalls = []
function disconnectRow(ssid) { actionCalls.push('disconnect:' + ssid) }
function forget(net) { actionCalls.push('forget:' + net.ssid) }
eval(activateSelectedFunction[0])
activateSelected()
assertDeepEqual(actionCalls, ['disconnect:Home'], 'network Enter disconnects a connected row')

actionCalls = []
wifiActionFocused = true
activateSelected()
assertDeepEqual(actionCalls, ['forget:Home'], 'network Right+Enter forgets a connected row')

actionCalls = []
wifiActionFocused = true
wifiNetworks = [{ connected: false, known: true, ssid: 'Saved', security: security.Open }]
selectedIndex = 0
activateSelected()
assertDeepEqual(actionCalls, ['forget:Saved'], 'network Right+Enter forgets a saved disconnected row')

const forgetFunction = panelSource.match(/function forget\(net\) \{[\s\S]*?\n {2}\}/)
assert(forgetFunction, 'network has a Forget action')
var liveNetwork = {
  name: 'Home',
  connected: true,
  known: true,
  stateChanging: false,
  disconnect: function() { forgetCalls.push('disconnect') },
  forget: function() { forgetCalls.push('forget') }
}
var forgetCalls = []
function networkForSsid(ssid) { return ssid === 'Home' ? liveNetwork : null }
function runNetworkAction(kind, network, callback) {
  forgetCalls.push('phase:' + kind)
  if (network) callback(network)
}
eval(forgetFunction[0])
forget({ ssid: 'Home' })
assertDeepEqual(
  forgetCalls,
  ['phase:forget-after-disconnect', 'disconnect'],
  'network starts connected Forget by disconnecting without racing the serialized Forget action'
)

forgetCalls = []
liveNetwork.connected = false
forget({ ssid: 'Home' })
assertDeepEqual(
  forgetCalls,
  ['phase:forget', 'forget'],
  'network forgets an already disconnected saved network directly'
)

const continueForget = panelSource.match(/function continueForgetAfterDisconnect\(ssid\) \{[\s\S]*?\n {2}\}/)
assert(continueForget, 'network has a second Forget phase after connected-network disconnection')
var actionKind = 'forget-after-disconnect'
var actionSsid = 'Home'
var clearCount = 0
function clearNetworkAction() { clearCount += 1; actionKind = ''; actionSsid = '' }
forgetCalls = []
liveNetwork.forget = function() { forgetCalls.push('forget-during:' + actionKind) }
eval(continueForget[0])
continueForgetAfterDisconnect('Home')
assertDeepEqual(
  forgetCalls,
  ['forget-during:forget'],
  'network enters the Forget phase before deleting the disconnected profile'
)
assertEqual(clearCount, 0, 'network keeps the action pending until profile deletion completes')

const checkActionCompletionFunction = panelSource.match(/function checkActionCompletion\(network\) \{[\s\S]*?\n {2}\}/)
assert(
  checkActionCompletionFunction &&
    /actionKind === "forget-after-disconnect"[\s\S]*!network\.connected[\s\S]*!network\.stateChanging[\s\S]*continueForgetAfterDisconnect/.test(checkActionCompletionFunction[0]),
  'network waits for disconnection to settle before continuing Forget'
)

const reasons = { NoSecrets: 1, WifiAuthTimeout: 2, WifiNetworkLost: 3, WifiClientDisconnected: 4, WifiClientFailed: 5 }
assertEqual(network.networkFailureReason(reasons.NoSecrets, true, reasons), 'Passphrase required', 'network maps missing credential failures')
assertEqual(network.networkFailureReason(reasons.WifiAuthTimeout, true, reasons), 'Wrong password', 'network maps credentialed auth timeouts')
assertEqual(network.networkFailureReason(reasons.NoSecrets, false, reasons), 'Failed to connect', 'network gives passwordless missing-secret failures generic copy')
assertEqual(network.networkFailureReason(reasons.WifiAuthTimeout, false, reasons), 'Failed to connect', 'network gives passwordless auth timeouts generic copy')
assertEqual(network.networkFailureReason(99, true, reasons), 'Failed to connect', 'network maps unknown failures')

assertEqual(network.canForgetNetwork({ known: true, connected: false, security: security.Owe }), true, 'network can forget known disconnected OWE networks')
assertEqual(network.canForgetNetwork({ known: true, connected: false, security: security.Open }), true, 'network can forget known disconnected open networks')
assertEqual(network.canForgetNetwork({ known: false, connected: false, security: security.Owe }), false, 'network cannot forget unknown networks')
assertEqual(network.canForgetNetwork({ known: true, connected: true, security: security.Owe }), false, 'network keeps connected profiles out of the direct Forget path')

assertEqual(network.shouldRepromptPassphrase(reasons.NoSecrets, true, reasons), true, 'network reprompts when required credentials are missing')
assertEqual(network.shouldRepromptPassphrase(reasons.NoSecrets, false, reasons), false, 'network does not ask a passwordless network for missing secrets')
assertEqual(network.shouldRepromptPassphrase(reasons.WifiAuthTimeout, true, reasons), true, 'network reprompts a credentialed network after a wrong password')
assertEqual(network.shouldRepromptPassphrase(reasons.WifiAuthTimeout, false, reasons), false, 'network does not reprompt an open network on auth timeout')
assertEqual(network.shouldRepromptPassphrase(reasons.WifiClientFailed, true, reasons), false, 'network does not reprompt on generic connection failures')


assertEqual(network.bandLabel('2.4'), '2.4ghz', 'network labels the 2.4GHz band')
assertEqual(network.bandLabel('6'), '6ghz', 'network labels the 6GHz band')
assertEqual(network.bandLabel('auto'), 'Auto', 'network labels the automatic band choice')

assertEqual(network.bandSectionTitle('auto', '2.4'), 'WI-FI BAND: 2.4GHZ', 'network names the live band in the header under automatic')
assertEqual(network.bandSectionTitle('auto', ''), 'WI-FI BAND', 'network omits an unknown band from the header')
assertEqual(network.bandSectionTitle('5', '5'), 'WI-FI BAND', 'network drops the header band once the pills are showing')
assertEqual(network.bandSectionTitle('5', '2.4'), 'WI-FI BAND', 'network keeps a plain header while a pin is settling')

assertDeepEqual(
  network.parseBandStatus('band\t5\navailable\t2.4 5 6\nselected\tauto\n'),
  { band: '5', selected: 'auto', available: ['2.4', '5', '6'] },
  'network parses band status'
)
assertDeepEqual(
  network.parseBandStatus(''),
  { band: '', selected: 'auto', available: [] },
  'network parses empty band status without a wifi connection'
)



assertEqual(network.headerDetail({ type: 'wifi', freq: '5745' }), '', 'network keeps wifi band state out of the hero')
assertEqual(network.headerDetail({ type: 'ethernet', speed: '100' }), '100mbit', 'network keeps ethernet speed in the hero')
JS
