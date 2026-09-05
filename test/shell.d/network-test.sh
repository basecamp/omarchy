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

// scannerEnabled is a plain shared bool on a WifiDevice, and this widget is
// instantiated once per monitor, so ownership is reference counted in
// Scanner.js. Load that module the way the QML engine does -- one shared scope
// for every instance -- and drive it with stand-in panels and devices.
const scannerSource = fs.readFileSync(root + '/shell/plugins/panels/network/Scanner.js', 'utf8')
assert(/^\.pragma library/m.test(scannerSource), 'network scanner claims share one engine-wide scope')

function loadScanner() {
  const body = scannerSource.replace(/^\.pragma library/m, '')
  return new Function(body + '\nreturn { acquire, release, claimCount, sweep }')()
}

const scannerHelper = panelSource.match(/function setScannerEnabled\(enabled\) \{[\s\S]*?\n {2}\}/)
assert(scannerHelper, 'network has a scanner ownership helper')
assert(/Scanner\.acquire\(root,/.test(scannerHelper[0]), 'network claims the scanner through the reference-counted registry')

// Bind the helper's free variables explicitly rather than leaking a `root`
// into this scope, so the panel under test is the stand-in and not the suite.
function bindSetScannerEnabled(Scanner, panel, opened, wifiDevice, scanPulsed, scanPulseActive) {
  // A claim counts only while its owner reports itself open, so the stand-in
  // has to carry the same state the helper is being handed. scanPulsed defaults
  // to false, which is the shipped default (scanHoldSec 0) and the behaviour
  // every case below this one asserts.
  panel.opened = opened
  return new Function(
    'Scanner', 'root', 'opened', 'wifiDevice', 'scanPulsed', 'scanPulseActive',
    scannerHelper[0] + '\nreturn setScannerEnabled'
  )(Scanner, panel, opened, wifiDevice, !!scanPulsed, !!scanPulseActive)
}

// A closed panel must never claim the scanner, whatever it asks for.
var Scanner = loadScanner()
const closedPanel = { name: 'closed' }
const idleDevice = { scannerEnabled: false }
bindSetScannerEnabled(Scanner, closedPanel, false, idleDevice)(true)
assert(
  idleDevice.scannerEnabled === false && Scanner.claimCount(idleDevice) === 0,
  'network does not let a closed panel claim or enable a scanner device'
)

// Adopting a replacement device must release the one left behind.
Scanner = loadScanner()
const openPanel = { name: 'open' }
const previousScannerDevice = { scannerEnabled: false }
const replacementScannerDevice = { scannerEnabled: false }
bindSetScannerEnabled(Scanner, openPanel, true, previousScannerDevice)(true)
bindSetScannerEnabled(Scanner, openPanel, true, replacementScannerDevice)(true)
assert(
  previousScannerDevice.scannerEnabled === false &&
    replacementScannerDevice.scannerEnabled === true &&
    Scanner.claimCount(previousScannerDevice) === 0,
  'network releases the previous scanner device before enabling its replacement'
)

// Closing releases: the same panel asking with opened=false drops its claim.
bindSetScannerEnabled(Scanner, openPanel, false, replacementScannerDevice)(false)
assert(
  replacementScannerDevice.scannerEnabled === false &&
    Scanner.claimCount(replacementScannerDevice) === 0,
  'network releases the scanner when its panel closes'
)

// The bug this reference counting exists for: one panel per monitor sharing a
// device. Whoever closes first must not stop the scan the other is watching,
// and the last one out must stop it. Without counting, either the scanner dies
// under an open panel or it runs on forever behind a closed one.
Scanner = loadScanner()
var sharedDevice = { scannerEnabled: false }
var panelA = { name: 'a', opened: true }
var panelB = { name: 'b', opened: true }
Scanner.acquire(panelA, sharedDevice)
Scanner.acquire(panelB, sharedDevice)
Scanner.release(panelA)
assert(sharedDevice.scannerEnabled === true, 'network keeps scanning while another monitor still has the panel open')
Scanner.release(panelB)
assert(sharedDevice.scannerEnabled === false, 'network stops scanning once the last open panel lets go')

// Releasing twice must not disturb a claim someone else has since taken.
Scanner.release(panelB)
Scanner.acquire(panelA, sharedDevice)
Scanner.release(panelB)
assert(sharedDevice.scannerEnabled === true, 'network ignores a repeated release from an instance holding no claim')
Scanner.release(panelA)

// A device destroyed underneath a live claim throws on property access rather
// than reading back null; releasing it must not take the shell down with it.
Scanner = loadScanner()
var destroyedDevice = {
  get scannerEnabled() { throw new TypeError('Cannot read property of null') },
  set scannerEnabled(value) { throw new TypeError('Cannot write property of null') }
}
Scanner.acquire(panelA, destroyedDevice)
Scanner.release(panelA)
pass('network survives releasing a device that was destroyed underneath it')

// Destruction is the case a guard-only fix misses: the widget dies with the
// panel still open, as a bar reload does, and nothing else would release it.
assert(
  /Component\.onDestruction: Scanner\.release\(root\)/.test(panelSource),
  'network releases the scanner it owns when the widget is destroyed'
)
assert(!/wifiDevice\.scannerEnabled\s*=/.test(panelSource), 'network writes scanner state through the registry rather than the moving wifiDevice reference')

// A claim is only as good as its owner. An instance that dies without its
// release running, or one whose release is simply missed, must not be able to
// pin the scanner on -- that is the exact failure #7896 describes.
Scanner = loadScanner()
const abandonedDevice = { scannerEnabled: false }
const doomedPanel = { opened: true }
Scanner.acquire(doomedPanel, abandonedDevice)
assert(abandonedDevice.scannerEnabled === true, 'network scans while an open panel holds the claim')

// Destroyed: property access throws rather than reading back null.
Object.defineProperty(doomedPanel, 'opened', {
  get() { throw new TypeError('Cannot read property of null') },
  configurable: true
})
Scanner.sweep(abandonedDevice)
assert(
  abandonedDevice.scannerEnabled === false && Scanner.claimCount(abandonedDevice) === 0,
  'network drops the claim of an owner destroyed without releasing'
)

// Closed but never released: same outcome, without the destruction.
Scanner = loadScanner()
const forgottenDevice = { scannerEnabled: false }
const forgottenPanel = { opened: true }
Scanner.acquire(forgottenPanel, forgottenDevice)
forgottenPanel.opened = false
Scanner.sweep(forgottenDevice)
assert(forgottenDevice.scannerEnabled === false, 'network drops a claim whose panel closed without releasing')

// A device enabled out of band with nothing claiming it must still be driven
// off -- releasing alone never touches a device the registry has no claim for.
Scanner = loadScanner()
const strayDevice = { scannerEnabled: true }
Scanner.sweep(strayDevice)
assert(strayDevice.scannerEnabled === false, 'network turns off a scanner nothing is claiming')

// The sweep must not be indiscriminate: a live open panel keeps its scan.
Scanner = loadScanner()
const sharedLive = { scannerEnabled: false }
const stillOpen = { opened: true }
const alsoDead = { opened: true }
Scanner.acquire(stillOpen, sharedLive)
Scanner.acquire(alsoDead, sharedLive)
Object.defineProperty(alsoDead, 'opened', {
  get() { throw new TypeError('Cannot read property of null') },
  configurable: true
})
Scanner.sweep(sharedLive)
assert(
  sharedLive.scannerEnabled === true && Scanner.claimCount(sharedLive) === 1,
  'network sweeps the dead owner but keeps scanning for the open one'
)

// The scanner is shared mutable state on a long-lived device, so a missed
// release must not be able to leave the radio scanning indefinitely.
const scannerReconcile = panelSource.match(/Timer \{\s*interval: 30000[\s\S]*?\n {2}\}/)
assert(scannerReconcile, 'network re-asserts scanner state on a timer so a stale claim cannot persist')
assert(/running: true/.test(scannerReconcile[0]), 'network runs the scanner reconcile whether or not its panel is open')
assert(/Scanner\.sweep\(root\.wifiDevice\)/.test(scannerReconcile[0]), 'network sweeps dead claims on reconcile rather than only re-asserting its own')
// Reconciling inside the deferred-restart window would re-enable the scanner
// early and undo the deferral that keeps panel opening off the AP flood.
assert(/if \(scanRestart\.running\) return/.test(scannerReconcile[0]), 'network skips reconciling while a deferred scan restart is pending')

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
assert(
  /readonly property bool canForget: root\.canForgetNetwork\(net\)/.test(panelSource),
  'network rows derive forget eligibility from the tested model helper'
)
const rightAction = panelSource.match(/Item \{\s*id: rightAction\b[\s\S]*?\n {6}\}/)
assert(rightAction, 'network has a right-edge action target')
assert(
  /visible: row\.requiresCredentials \|\| row\.canForget/.test(rightAction[0]),
  'network keeps a forget target for known passwordless networks'
)
const lockIndicator = panelSource.match(/Text \{\s*id: lockIndicator\b[\s\S]*?\n {8}\}/)
assert(lockIndicator, 'network has a lock/forget indicator')
assert(
  /visible: row\.requiresCredentials \|\| row\.forgetVisible/.test(lockIndicator[0]),
  'network hides the lock on passwordless networks until showing their forget action'
)
assert(
  /forgetVisible: canForget && \(!requiresCredentials \|\| forgetFocused \|\| rightMouse\.containsMouse\)/.test(panelSource),
  'network shows the forget action directly for known passwordless networks'
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
assertEqual(network.canForgetNetwork({ known: true, connected: true, security: security.Owe }), false, 'network cannot forget the connected network')

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

// scanHoldSec turns the claim into a pulse. The point of the setting is that a
// panel can be open without the radio being off-channel, so an open panel with
// no pulse running must not claim -- the case that is a plain bug when the
// setting is off.
Scanner = loadScanner()
const heldDevice = { scannerEnabled: false }
const heldPanel = { name: 'held' }
bindSetScannerEnabled(Scanner, heldPanel, true, heldDevice, true, false)(true)
assert(
  heldDevice.scannerEnabled === false && Scanner.claimCount(heldDevice) === 0,
  'network does not claim the scanner for an open panel once its pulse has expired'
)

Scanner = loadScanner()
const pulsingDevice = { scannerEnabled: false }
const pulsingPanel = { name: 'pulsing' }
bindSetScannerEnabled(Scanner, pulsingPanel, true, pulsingDevice, true, true)(true)
assert(
  pulsingDevice.scannerEnabled === true && Scanner.claimCount(pulsingDevice) === 1,
  'network claims the scanner while a pulse is live'
)

// A pulse cannot resurrect a closed panel's claim either.
Scanner = loadScanner()
const closedPulseDevice = { scannerEnabled: false }
bindSetScannerEnabled(Scanner, { name: 'closed-pulse' }, false, closedPulseDevice, true, true)(true)
assert(
  closedPulseDevice.scannerEnabled === false && Scanner.claimCount(closedPulseDevice) === 0,
  'network keeps a closed panel from claiming even with a pulse marked live'
)

// The defaults have to reproduce the old behaviour exactly, or this setting is
// a silent regression for everyone who never sets it.
const networkManifest = JSON.parse(fs.readFileSync(root + '/shell/plugins/panels/network/manifest.json', 'utf8'))
assertEqual(networkManifest.barWidget.defaults.scanOnOpen, true, 'network still scans on open by default')
assertEqual(networkManifest.barWidget.defaults.scanHoldSec, 0, 'network still holds the scanner while open by default')
assert(
  /settings\.scanOnOpen/.test(panelSource) && /settings\.scanHoldSec/.test(panelSource),
  'network reads both scan settings from its widget config'
)
assert(
  /refresh\(scanOnOpen\)/.test(panelSource),
  'network routes the panel-open scan through the scanOnOpen setting'
)

// A scan the panel no longer starts on its own needs something to press, and
// the keyboard path alone leaves mouse users with no way to rescan at all.
assert(/id: rescanAction/.test(panelSource), 'network offers a rescan button in the panel header')
const rescanButton = panelSource.match(/Button \{\s*\n\s*id: rescanAction[\s\S]*?\n {10}\}/)
assert(rescanButton, 'network rescan button is a complete header action')
assert(/onClicked: root\.refresh\(true\)/.test(rescanButton[0]), 'network rescan button starts a real sweep')
assert(/visible: root\.canRescanWifi/.test(rescanButton[0]), 'network shows the rescan button whenever there is a radio to scan with')
assert(/tooltipText:[^\n]*\(r\)/.test(rescanButton[0]), 'network rescan button names its keyboard shortcut')

const activateHeaderFn = panelSource.match(/function activateHeader\(\)[\s\S]*?\n {2}\}/)
assert(activateHeaderFn, 'network has an activateHeader dispatcher')
assert(
  /headerIndex === rescanHeaderIndex\) refresh\(true\)/.test(activateHeaderFn[0]),
  'network keyboard-activates the rescan header action'
)
assert(
  /headerActionCount:[^\n]*canRescanWifi/.test(panelSource),
  'network counts the rescan action so header navigation can reach it'
)
JS
