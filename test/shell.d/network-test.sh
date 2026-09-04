#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const network = requireFromRoot('shell/plugins/panels/network/Model.js')
const panelSource = fs.readFileSync(root + '/shell/plugins/panels/network/Panel.qml', 'utf8')

assert(/IpcHandler[\s\S]*?function toggleNetwork\(\) \{ root\.toggleNetwork\(\) \}/.test(panelSource), 'network exposes the Wi-Fi radio toggle over IPC')
assert(/manageIpc: false/.test(panelSource), 'network owns its IPC handler so it can extend the target methods')

// The hidden-network form is appended at the bottom of the panel's content,
// so on a short display it can fall outside the card's capped height with no
// way to reach it. The main column must live inside a Flickable (not a bare
// Column) so it has a scroll path -- a future edit flattening it back out
// must fail here.
const mainColumn = panelSource.match(/Flickable \{\s*id: panelFlick[\s\S]*?Column \{\s*id: column\b/)
assert(mainColumn, 'network wraps its main column in a Flickable so overflow content stays reachable')
assert(/interactive: contentHeight > height/.test(mainColumn[0]), 'network only lets the outer Flickable drag when its content overflows')

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

// Hidden-network connect script: SSID must travel as a positional arg --
// never string-interpolated -- and the profile must be marked hidden so
// NetworkManager probes for it instead of waiting on a beacon that will
// never arrive.
assert(/"\$1"/.test(network.hiddenPskConnectScript), 'hidden PSK connect script maps ssid to the positional $1 arg')
assert(/802-11-wireless\.hidden yes/.test(network.hiddenPskConnectScript), 'hidden PSK connect script marks the profile hidden')
assert(/IFS= read -r pw/.test(network.hiddenPskConnectScript), 'hidden PSK connect script reads the passphrase from stdin, not argv')
assert(/set wifi-sec\.psk %s/.test(network.hiddenPskConnectScript), 'hidden PSK connect script sets the psk through the connection editor')
assert(!/password "\$pw"/.test(network.hiddenPskConnectScript), 'hidden PSK connect script never passes the passphrase in argv')

// One script serves both WPA/WPA2 Personal and WPA3 Personal: key-mgmt comes
// from the caller-supplied $2 ("wpa-psk" or "sae"), and WPA3 additionally
// requires Protected Management Frames, set only in the sae case.
assert(/wifi-sec\.key-mgmt "\$2"/.test(network.hiddenPskConnectScript), 'hidden PSK connect script sets key-mgmt from the $2 arg, not a hardcoded value')
assert(!/wifi-sec\.key-mgmt wpa-psk/.test(network.hiddenPskConnectScript), 'hidden PSK connect script no longer hardcodes wpa-psk as the key-mgmt')
assert(/\[\[ \$2 == "sae" \]\] && pmf="wifi-sec\.pmf 3"/.test(network.hiddenPskConnectScript), 'hidden PSK connect script sets PMF required only for the sae (WPA3) case, using a [[ ]] string test per AGENTS.md')

// Dedupe must never delete by con-name (not unique -- could hit an unrelated
// profile): match prior profiles by UUID over (ssid, hidden), and only once
// the new one is up. Enumeration is two fixed nmcli calls, never one per
// connection.
assert(!/connection delete id "\$1"/.test(network.hiddenPskConnectScript), 'hidden PSK connect script never deletes an existing profile by name')
assert(!network.hiddenPskConnectScript.includes('connection delete id '), 'hidden PSK connect script never deletes any existing profile by name (id), regardless of the argument')
assert(/nmcli -t -f UUID,TYPE connection show/.test(network.hiddenPskConnectScript), 'hidden PSK connect script lists all connections (UUID + type) in a single nmcli call')
assert(network.hiddenPskConnectScript.includes('done < <(nmcli -t -f UUID,TYPE connection show)'), 'hidden PSK connect script reads the dedupe queries through process substitution, keeping bash in an interruptible read instead of waiting on a foreground command substitution')
assert(network.hiddenPskConnectScript.includes('done < <(LC_ALL=C nmcli --escape no -g'), 'hidden PSK connect script reads the dedupe queries through process substitution, keeping bash in an interruptible read instead of waiting on a foreground command substitution')
assert(network.hiddenPskConnectScript.includes('>/dev/null & wait $!; }'), 'hidden PSK connect script backgrounds connection add under wait so the TERM trap can preempt it')
assert(network.hiddenPskConnectScript.includes('nmcli connection edit uuid "$u" >/dev/null & wait $!; }'), 'hidden PSK connect script backgrounds connection edit under wait so the TERM trap can preempt it')
assert(network.hiddenPskConnectScript.includes('trap \'timeout -k 1 5 nmcli connection delete uuid "$u"'), 'hidden PSK connect script bounds the EXIT-trap cleanup delete so a wedged NetworkManager cannot stall the dying process')
assert(!/for c in \$\(nmcli/.test(network.hiddenPskConnectScript), 'hidden PSK connect script never runs nmcli once per connection (N+1)')
assert(/nmcli --escape no -g connection\.uuid,802-11-wireless\.ssid,802-11-wireless\.hidden,802-11-wireless-security\.key-mgmt,802-11-wireless\.bssid,802-11-wireless\.mac-address,connection\.interface-name,ipv4\.method,ipv6\.method,ipv4\.addresses,ipv4\.dns,ipv4\.routes,ipv6\.addresses,ipv6\.dns,ipv6\.routes connection show \$wifi/.test(network.hiddenPskConnectScript), 'hidden PSK connect script fetches ssid/hidden/identity/IP-customization fields for all wifi profiles in one batched, unescaped query so a colon/backslash SSID still compares equal to the raw $1')
assert(/\[\[ \$t == "802-11-wireless" \]\] && wifi=/.test(network.hiddenPskConnectScript), 'hidden PSK connect script only considers 802-11-wireless connections for cleanup')
assert(/\[\[ \$ssid == "\$1" \]\] \|\| continue/.test(network.hiddenPskConnectScript), 'hidden PSK connect script matches prior profiles by this SSID, not by name')
assert(/\[\[ \$hidden == "yes" \]\] \|\| continue/.test(network.hiddenPskConnectScript), 'hidden PSK connect script only considers hidden profiles for cleanup, never a broadcast network of the same SSID')
assert(/old="\$old uuid \$c"/.test(network.hiddenPskConnectScript), 'hidden PSK connect script accumulates old profiles as delete-ready "uuid <id>" tokens')
assert(!/for o in \$old/.test(network.hiddenPskConnectScript), 'hidden PSK connect script deletes duplicates in one batched nmcli call, not one per profile')
assert(/connection up uuid "\$u"[\s\S]*nmcli connection delete \$old/.test(network.hiddenPskConnectScript), 'hidden PSK connect script only deletes old profiles after the new one activates successfully')

// Cleanup is a single EXIT trap: armed before the profile exists, deleting
// it on any failure or TERM/INT kill, and disarmed (`trap - EXIT`) only
// after `connection up` proves it. `true` pins the success block's status
// so a stale old-UUID delete can't flip the chain to failure.
assert(/trap 'timeout -k 1 5 nmcli connection delete uuid "\$u"[^']*' EXIT/.test(network.hiddenPskConnectScript), 'hidden PSK connect script arms an EXIT trap that removes the unproven profile on any failure or kill')
assert(/trap 'kill -TERM \$! 2>\/dev\/null; exit 143' TERM INT/.test(network.hiddenPskConnectScript), 'hidden PSK connect script\'s TERM trap kills the in-flight nmcli so a panel kill is never deferred behind a foreground child')
assert(
  network.hiddenPskConnectScript.indexOf("' EXIT") < network.hiddenPskConnectScript.indexOf('connection add'),
  'hidden PSK connect script arms the cleanup trap before the profile is created'
)
assert(
  network.hiddenPskConnectScript.indexOf('connection up uuid "$u"') < network.hiddenPskConnectScript.indexOf('trap - EXIT'),
  'hidden PSK connect script disarms the cleanup trap only after connection up proves the profile'
)
assert(/\[\[ -n \$old \]\] && nmcli connection delete \$old[\s\S]*true; \}/.test(network.hiddenPskConnectScript), 'hidden PSK connect script pins the success block status with `true` so a stale old-UUID delete failure cannot fail the chain')

// The profile starts inert (autoconnect no), is armed only after activation,
// and old profiles are removed only if that arm succeeded -- a failed arm
// keeps the old, still-autoconnecting profiles. `-w 25` keeps nmcli under
// the QML 30s kill.
assert(/connection\.autoconnect no/.test(network.hiddenPskConnectScript), 'hidden PSK connect script creates the profile inert (autoconnect no) so a killed/failed attempt cannot be retried in the background')
assert(/nmcli -w 25 connection up uuid "\$u"/.test(network.hiddenPskConnectScript), 'hidden PSK connect script bounds nmcli\'s own wait below the QML 30s kill timeout')
assert(
  network.hiddenPskConnectScript.indexOf('connection up uuid "$u"') < network.hiddenPskConnectScript.indexOf('connection.autoconnect yes'),
  'hidden PSK connect script only sets autoconnect yes after connection up, never before'
)
assert(/if nmcli connection modify uuid "\$u" connection\.autoconnect yes[\s\S]*nmcli connection delete \$old/.test(network.hiddenPskConnectScript), 'hidden PSK connect script deletes old profiles only if the autoconnect arm succeeded')

// IFS= on every field read: a bare `read` trims whitespace and would corrupt
// a space-padded SSID before the "$1" compare. The batched query blank-lines
// between profiles, so the uuid read skips blanks to keep 3-line groups aligned.
assert(/IFS= read -r ssid; IFS= read -r hidden;/.test(network.hiddenPskConnectScript), 'hidden PSK connect script parses ssid/hidden with IFS= read -r so a space-padded SSID is not trimmed')
assert(/\[\[ -n \$c \]\] \|\| continue/.test(network.hiddenPskConnectScript), 'hidden PSK connect script skips the blank separator lines between batched profiles so field groups stay aligned')
assert(network.hiddenPskConnectScript.includes('[[ $c != "$u" ]] || continue'), 'hidden PSK connect script dedupe skips the profile this attempt just created, so the late snapshot cannot delete it')
assert(/if nmcli connection modify uuid "\$u" connection\.autoconnect yes[\s\S]*--escape no -g[\s\S]*nmcli connection delete \$old/.test(network.hiddenPskConnectScript), 'hidden PSK connect script snapshots duplicates inside the modify-success block, immediately before the batched delete (TOCTOU guard)')
assert(/connection modify[\s\S]*trap 'kill -TERM \$! 2>\/dev\/null; exit 143' TERM INT/.test(network.hiddenPskConnectScript), 'hidden PSK connect script re-arms the kill-child TERM trap before the late snapshot so a panel kill still interrupts it')

// An open hidden network has no credentials, but must still avoid `nmcli
// device wifi connect`, which persists an autoconnecting profile before
// activation -- a timed-out or killed attempt would stay saved and retry in
// the background. It shares the PSK script's dedupe/EXIT-trap lifecycle,
// minus the secret.
assert(/"\$1"/.test(network.hiddenOpenConnectScript), 'hidden open connect script maps ssid to the positional $1 arg')
assert(/802-11-wireless\.hidden yes/.test(network.hiddenOpenConnectScript), 'hidden open connect script marks the profile hidden')
assert(/connection\.autoconnect no/.test(network.hiddenOpenConnectScript), 'hidden open connect script creates the profile inert (autoconnect no) so a killed/failed attempt cannot be retried in the background')
assert(!/wifi-sec/.test(network.hiddenOpenConnectScript), 'hidden open connect script sets no wifi security properties on an open profile')
assert(!/IFS= read -r pw/.test(network.hiddenOpenConnectScript), 'hidden open connect script never reads a passphrase, since open networks have none')

assert(/trap 'timeout -k 1 5 nmcli connection delete uuid "\$u"[^']*' EXIT/.test(network.hiddenOpenConnectScript), 'hidden open connect script arms an EXIT trap that removes the unproven profile on any failure or kill')
assert(/trap 'kill -TERM \$! 2>\/dev\/null; exit 143' TERM INT/.test(network.hiddenOpenConnectScript), 'hidden open connect script\'s TERM trap kills the in-flight nmcli so a panel kill is never deferred behind a foreground child')
assert(
  network.hiddenOpenConnectScript.indexOf("' EXIT") < network.hiddenOpenConnectScript.indexOf('connection add'),
  'hidden open connect script arms the cleanup trap before the profile is created'
)
assert(
  network.hiddenOpenConnectScript.indexOf('connection up uuid "$u"') < network.hiddenOpenConnectScript.indexOf('trap - EXIT'),
  'hidden open connect script disarms the cleanup trap only after connection up proves the profile'
)
assert(/nmcli -w 25 connection up uuid "\$u"/.test(network.hiddenOpenConnectScript), 'hidden open connect script bounds nmcli\'s own wait below the QML 30s kill timeout')
assert(
  network.hiddenOpenConnectScript.indexOf('connection up uuid "$u"') < network.hiddenOpenConnectScript.indexOf('connection.autoconnect yes'),
  'hidden open connect script only sets autoconnect yes after connection up, never before'
)
assert(/if nmcli connection modify uuid "\$u" connection\.autoconnect yes[\s\S]*nmcli connection delete \$old/.test(network.hiddenOpenConnectScript), 'hidden open connect script deletes old profiles only if the autoconnect arm succeeded')

assert(/nmcli --escape no -g connection\.uuid,802-11-wireless\.ssid,802-11-wireless\.hidden,802-11-wireless-security\.key-mgmt,802-11-wireless\.bssid,802-11-wireless\.mac-address,connection\.interface-name,ipv4\.method,ipv6\.method,ipv4\.addresses,ipv4\.dns,ipv4\.routes,ipv6\.addresses,ipv6\.dns,ipv6\.routes connection show \$wifi/.test(network.hiddenOpenConnectScript), 'hidden open connect script shares the same batched dedupe query as the PSK script, so it dedupes prior hidden profiles too')
assert(network.hiddenOpenConnectScript.includes('done < <(nmcli -t -f UUID,TYPE connection show)'), 'hidden open connect script reads the dedupe queries through process substitution, keeping bash in an interruptible read instead of waiting on a foreground command substitution')
assert(network.hiddenOpenConnectScript.includes('done < <(LC_ALL=C nmcli --escape no -g'), 'hidden open connect script reads the dedupe queries through process substitution, keeping bash in an interruptible read instead of waiting on a foreground command substitution')
assert(network.hiddenOpenConnectScript.includes('>/dev/null & wait $!; }'), 'hidden open connect script backgrounds connection add under wait so the TERM trap can preempt it')
assert(network.hiddenOpenConnectScript.includes('trap \'timeout -k 1 5 nmcli connection delete uuid "$u"'), 'hidden open connect script bounds the EXIT-trap cleanup delete so a wedged NetworkManager cannot stall the dying process')
assert(network.hiddenOpenConnectScript.includes('[[ $c != "$u" ]] || continue'), 'hidden open connect script dedupe skips the profile this attempt just created, so the late snapshot cannot delete it')
assert(/if nmcli connection modify uuid "\$u" connection\.autoconnect yes[\s\S]*--escape no -g[\s\S]*nmcli connection delete \$old/.test(network.hiddenOpenConnectScript), 'hidden open connect script snapshots duplicates inside the modify-success block, immediately before the batched delete (TOCTOU guard)')
assert(/connection modify[\s\S]*trap 'kill -TERM \$! 2>\/dev\/null; exit 143' TERM INT/.test(network.hiddenOpenConnectScript), 'hidden open connect script re-arms the kill-child TERM trap before the late snapshot so a panel kill still interrupts it')
JS
