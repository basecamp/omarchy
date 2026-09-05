#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const panelSource = fs.readFileSync(root + '/shell/plugins/panels/network/Panel.qml', 'utf8')

// ---------------------------------------------------------------------------
// Multi-adapter selection. A machine can expose several Wi-Fi NICs (an onboard
// radio alongside a USB dongle), and the panel lets the user pick which one it
// acts on. These are the state-heavy paths that manual two-adapter poking does
// not protect from regressions.
// ---------------------------------------------------------------------------

function extract(pattern, label) {
  const match = panelSource.match(pattern)
  assert(match, label)
  return match[0]
}

function mkDevice(name, connected, networks) {
  return {
    name: name,
    type: 'wifi',
    connected: connected,
    networks: { values: networks || [] }
  }
}

function mkNetwork(connected, strength) {
  return { connected: connected, signalStrength: strength }
}

// --- device enumeration ----------------------------------------------------

// Pills must not reshuffle under the cursor when an adapter connects or drops,
// so the selector keeps NetworkManager's own order rather than sorting the
// connected device to the front.
const findAllSource = extract(
  /function findAllWifiDevices\(\) \{[\s\S]*?\n {2}\}/,
  'network has a findAllWifiDevices() helper'
)

var DeviceType = { Wifi: 'wifi', Wired: 'wired' }
var networkDevices = []
eval(findAllSource)

const onboard = mkDevice('wlp3s0', false)
const dongle = mkDevice('wlp0s20u1', true, [mkNetwork(true, 0.9)])
const wired = { name: 'enp0s1', type: 'wired', connected: true }

networkDevices = [onboard, dongle, wired]
var enumerated = findAllWifiDevices()
assert(
  enumerated.length === 2 && enumerated[0] === onboard && enumerated[1] === dongle,
  'network enumerates every Wi-Fi device in backend order and skips other device types'
)

networkDevices = [dongle, onboard]
enumerated = findAllWifiDevices()
assert(
  enumerated[0] === dongle && enumerated[1] === onboard,
  'network does not reorder the adapter list when the connected device is not first'
)

// --- selection resolution --------------------------------------------------

// Selection is pinned by interface name: the device list can change length as
// adapters come and go, and an index would silently name a different NIC.
const selectedSource = extract(
  /readonly property var selectedWifiDevice: \{[\s\S]*?\n {2}\}/,
  'network resolves a selected Wi-Fi device'
)
const selectedBody = selectedSource.replace(
  /^\s*readonly property var selectedWifiDevice: \{/,
  ''
).replace(/\n {2}\}$/, '')

function resolveSelected(devices, pinned) {
  var allWifiDevices = devices
  var selectedWifiIface = pinned
  return new Function('allWifiDevices', 'selectedWifiIface', selectedBody)(
    allWifiDevices, selectedWifiIface
  )
}

const pair = [onboard, dongle]

// With nothing pinned the panel must behave exactly as it did before the
// selector existed: prefer whichever adapter is actually connected.
assert(
  resolveSelected(pair, '') === dongle,
  'network falls back to the connected adapter when no interface is pinned'
)
assert(
  resolveSelected(pair, 'wlp3s0') === onboard,
  'network honours a pinned interface even when it is not the connected one'
)

// Hot-unplugging the pinned adapter must not leave the panel pointing at a
// device that no longer exists.
assert(
  resolveSelected(pair, 'wlp-removed') === dongle,
  'network falls back to the connected adapter when the pinned interface is gone'
)
assert(
  resolveSelected([onboard], 'wlp-removed') === onboard,
  'network falls back to the first adapter when nothing is connected'
)
assert(
  resolveSelected([], 'wlp3s0') === null,
  'network resolves no device when there are no Wi-Fi adapters'
)

// --- cross-device connectivity --------------------------------------------

// The bar answers "am I online", which does not change because the panel is
// listing a different NIC. Deriving it from the selected device made the bar
// show the crossed-out glyph whenever an idle adapter was on screen.
const anyConnectedSource = extract(
  /readonly property bool anyWifiConnected: \{[\s\S]*?\n {2}\}/,
  'network tracks whether any Wi-Fi adapter is connected'
)
const anyConnectedBody = anyConnectedSource.replace(
  /^\s*readonly property bool anyWifiConnected: \{/,
  ''
).replace(/\n {2}\}$/, '')

function anyConnected(devices) {
  return new Function('allWifiDevices', anyConnectedBody)(devices)
}

assert(
  anyConnected([onboard, dongle]) === true,
  'network reports Wi-Fi connectivity from a non-selected adapter'
)
assert(
  anyConnected([onboard, mkDevice('wlp1s0', false)]) === false,
  'network reports no Wi-Fi connectivity when every adapter is down'
)

// --- cross-device signal strength ----------------------------------------

// A WifiNetwork only reports connected == true on a device whose scanner the
// panel enabled, and the panel only scans the selected device. A connected
// adapter the user is not looking at therefore publishes its networks with the
// flag unset -- but they still carry a live signalStrength.
const strengthSource = extract(
  /function findActiveWifiStrength\(\) \{[\s\S]*?\n {2}\}/,
  'network has a cross-device signal strength helper'
)

function activeStrength(devices) {
  var allWifiDevices = devices
  eval(strengthSource)
  return findActiveWifiStrength()
}

assert(
  activeStrength([onboard, dongle]) === 90,
  'network reads signal strength from the flagged network of a connected adapter'
)

const unscanned = mkDevice('wlp0s20u1', true, [
  mkNetwork(false, 0.4),
  mkNetwork(false, 0.85)
])
assert(
  activeStrength([onboard, unscanned]) === 85,
  'network falls back to the strongest published network when no flag is set'
)
assert(
  activeStrength([onboard]) === -1,
  'network reports unknown strength when no adapter is connected'
)
assert(
  activeStrength([mkDevice('wlp0s20u1', true, [])]) === -1,
  'network reports unknown strength when a connected adapter publishes no networks'
)

// --- helper command targeting --------------------------------------------

// omarchy-network-status derives its interface from the default route and
// omarchy-network-band takes the first connected Wi-Fi device, so both have to
// be told which adapter the panel is acting on or they silently report and
// modify a different one.
const statusCommandSource = extract(
  /function statusCommand\(verbose\) \{[\s\S]*?\n {2}\}/,
  'network builds its status command'
)
const bandCommandSource = extract(
  /function bandCommand\(band\) \{[\s\S]*?\n {2}\}/,
  'network builds its band command'
)

function buildCommands(iface) {
  var selectedIface = iface
  eval(statusCommandSource)
  eval(bandCommandSource)
  return {
    status: statusCommand(true).join(' '),
    bandStatus: bandCommand('').join(' '),
    bandSet: bandCommand('5').join(' ')
  }
}

var pinned = buildCommands('wlp3s0')
assert(
  pinned.status === 'omarchy-network-status --verbose --iface wlp3s0',
  'network pins the selected interface when reading connection details'
)
assert(
  pinned.bandStatus === 'omarchy-network-band --iface wlp3s0',
  'network pins the selected interface when reading the Wi-Fi band'
)
assert(
  pinned.bandSet === 'omarchy-network-band --iface wlp3s0 5',
  'network pins the selected interface when changing the Wi-Fi band'
)

var unpinned = buildCommands('')
assert(
  unpinned.status === 'omarchy-network-status --verbose',
  'network omits --iface entirely when it has no adapter to pin'
)
assert(
  unpinned.bandSet === 'omarchy-network-band 5',
  'network omits --iface from a band change when it has no adapter to pin'
)

// --- adapter toggle ------------------------------------------------------

// The toggle has to claim the panel's shared action guard: native
// WifiNetwork.connect() calls never touch actionProc, so a private guard would
// let a row action and an adapter toggle race.
const toggleSource = extract(
  /function toggleAdapter\(iface, enable\) \{[\s\S]*?\n {2}\}/,
  'network has an adapter toggle helper'
)

function runToggle(state, iface, enable) {
  var root = state
  var actionKind = state.actionKind
  var actionSsid = state.actionSsid
  var actionProc = state.actionProc
  var actionTimeout = { restart: function() { state.timeoutArmed = true } }

  eval(toggleSource)
  toggleAdapter(iface, enable)

  // The helper assigns the bare names for the shared guard.
  state.actionKind = actionKind
  state.actionSsid = actionSsid
  return state
}

function freshState() {
  return {
    actionKind: '',
    actionSsid: 'something',
    disabledAdapters: [],
    pendingAdapterIface: '',
    timeoutArmed: false,
    actionProc: { running: false, command: null }
  }
}

var state = runToggle(freshState(), 'wlp3s0', false)
assert(
  state.actionKind === 'adapter',
  'network claims the shared action guard while an adapter command is in flight'
)
assert(
  state.timeoutArmed === true,
  'network arms the action timeout so a stalled adapter command cannot wedge the panel'
)
assert(
  state.pendingAdapterIface === 'wlp3s0',
  'network records which adapter is being toggled'
)
assert(
  state.disabledAdapters.indexOf('wlp3s0') !== -1,
  'network marks the adapter off optimistically so the switch moves on click'
)
assert(
  Array.isArray(state.actionProc.command) &&
    state.actionProc.command.join(' ') === 'nmcli device disconnect wlp3s0',
  'network disconnects an adapter without routing the interface name through a shell'
)

state = runToggle(freshState(), 'wlp3s0', true)
assert(
  state.actionProc.command.join(' ') === 'nmcli device connect wlp3s0',
  'network reconnects an adapter through nmcli argv'
)
assert(
  state.disabledAdapters.indexOf('wlp3s0') === -1,
  'network clears the optimistic off state when reconnecting an adapter'
)

// A network row action already holds the guard: the toggle must not start.
var busy = freshState()
busy.actionKind = 'connect'
busy = runToggle(busy, 'wlp3s0', false)
assert(
  busy.actionProc.command === null && busy.pendingAdapterIface === '',
  'network refuses an adapter toggle while another action holds the shared guard'
)

// A device name is never interpolated into a shell string.
assert(
  !/bash", "-c", "nmcli/.test(panelSource) && !/nmcli device (connect|disconnect) " \+/.test(panelSource),
  'network never builds an nmcli adapter command by string concatenation'
)

// --- switch state reconciliation ----------------------------------------

// The switch must reflect NetworkManager, not a local wish-list: after a shell
// reload or an external `nmcli device disconnect`, showing "on" for a device
// that is actually down makes the first click issue a second disconnect.
const isEnabledSource = extract(
  /readonly property bool isEnabled: \{[\s\S]*?\n {4}\}/,
  'network derives the adapter switch state'
)
const isEnabledBody = isEnabledSource.replace(
  /^\s*readonly property bool isEnabled: \{/,
  ''
).replace(/\n {4}\}$/, '')

function switchOn(iface, isConnected, pendingIface, disabled) {
  return new Function(
    'iface', 'isConnected', 'root',
    isEnabledBody
  )(iface, isConnected, { pendingAdapterIface: pendingIface, disabledAdapters: disabled })
}

assert(
  switchOn('wlp3s0', false, '', []) === false,
  'network shows an adapter switch off when NetworkManager has the device disconnected'
)
assert(
  switchOn('wlp0s20u1', true, '', []) === true,
  'network shows an adapter switch on when the device is connected'
)
assert(
  switchOn('wlp3s0', false, 'wlp3s0', []) === true,
  'network shows the optimistic on state while a connect is in flight'
)
assert(
  switchOn('wlp0s20u1', true, 'wlp0s20u1', ['wlp0s20u1']) === false,
  'network shows the optimistic off state while a disconnect is in flight'
)
assert(
  switchOn('', false, '', []) === false,
  'network shows an adapter switch off when it has no interface name'
)

// --- keyboard focus safety ----------------------------------------------

// Hot-unplugging the adapter under the cursor can leave focusSection on a
// section that no longer renders, with an index past the end of the list.
const devicesChanged = extract(
  /onAllWifiDevicesChanged: \{[\s\S]*?\n {2}\}/,
  'network reacts to the adapter list changing'
)
assert(
  /adapterIndex/.test(devicesChanged),
  'network clamps the adapter cursor when the device list changes'
)
assert(
  /showAdapterSelector/.test(devicesChanged) && /focusSection/.test(devicesChanged),
  'network moves keyboard focus out of the adapter section when it disappears'
)

const timeoutHandler = extract(
  /id: actionTimeout[\s\S]*?onTriggered: \{[\s\S]*?\n {4}\}/,
  'network has an action timeout handler'
)
assert(
  /adapter/.test(timeoutHandler),
  'network releases the shared guard when an adapter command times out'
)
JS
