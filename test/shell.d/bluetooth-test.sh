#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

grep -q '^ConditionPathIsDirectory=/sys/class/bluetooth$' "$ROOT/default/systemd/user/bt-agent.service" || \
  fail "bt-agent is skipped on machines without Bluetooth hardware"
pass "bt-agent is skipped on machines without Bluetooth hardware"

run_node_test <<'JS'
const fs = require('fs')
const bluetooth = requireFromRoot('shell/plugins/panels/bluetooth/Model.js')
const panelSource = fs.readFileSync(root + '/shell/plugins/panels/bluetooth/Panel.qml', 'utf8')

assert(/IpcHandler[\s\S]*?function toggleBluetooth\(\) \{ root\.toggleBluetooth\(\) \}/.test(panelSource), 'bluetooth exposes the radio toggle over IPC')
assert(/manageIpc: false/.test(panelSource), 'bluetooth owns its IPC handler so it can extend the target methods')

// Writing adapter.enabled sets BlueZ Powered, which does not survive a reboot.
assert(/function toggleBluetooth\(\)[\s\S]*?execDetached\(\["omarchy-bluetooth-power", adapter\.enabled \? "off" : "on"\]\)/.test(panelSource), 'bluetooth toggles the radio through the rfkill soft block')
assert(!/adapter\.enabled = /.test(panelSource), 'bluetooth never writes the adapter power state directly')

// Discovery is a BlueZ session that nothing ends at panel close: it persists
// until StopDiscovery or until quickshell's D-Bus connection drops with the
// shell, and a leaked session keeps the radio in inquiry, starving A2DP audio
// on the same controller. The panel tracks the stop it owes and settles it
// once closed.
const retryTimer = panelSource.match(/id: discoveryRetry[\s\S]*?onTriggered: \{[\s\S]*?\n {4}\}/)
assert(retryTimer, 'bluetooth has the discovery retry timer')
assert(/owesDiscoveryStop = true/.test(retryTimer[0]), 'bluetooth takes on the stop it owes when it starts discovery')

// Quickshell only forwards a discovering write that differs from BlueZ's last
// confirmed state, so a stop written in the same instant as an in-flight
// StartDiscovery would be swallowed. Binding the stop timer to the confirmed
// state means a confirmation landing at any point after close re-arms it.
const stopTimer = panelSource.match(/id: discoveryStop[\s\S]*?onTriggered: \{[\s\S]*?\n {4}\}/)
assert(stopTimer, 'bluetooth has the discovery stop timer')
assert(/running: !root\.opened && root\.owesDiscoveryStop[\s\S]*discovering === true/.test(stopTimer[0]), 'bluetooth arms the stop off the confirmed discovery state while closed')
assert(/discovering = false/.test(stopTimer[0]), 'bluetooth stops discovery after the panel closes')

// One widget instance exists per monitor and they share the default adapter,
// so a closing instance hands the scan to a panel still open on another
// monitor instead of stopping it — that is the popout handoff between
// monitors.
assert(/function openSibling\(\)/.test(panelSource), 'bluetooth can see panel instances on other monitors')
assert(/sibling\.owesDiscoveryStop = true/.test(stopTimer[0]), 'bluetooth moves the stop it owes to an open panel on another monitor instead of stopping its scan')

// The debt clears when BlueZ confirms discovery down, and a destroyed
// instance hands it to a surviving sibling instead of taking it to the grave.
assert(/onDiscoveringChanged[\s\S]{0,120}owesDiscoveryStop = false/.test(panelSource), 'bluetooth settles the stop it owes once discovery is confirmed down')
assert(/Component\.onDestruction: \{[\s\S]{0,400}owesDiscoveryStop = true[\s\S]{0,200}discovering = false/.test(panelSource), 'bluetooth passes the stop it owes to a sibling when an instance is destroyed')

assert(bluetooth.isUuidLike('0000110b-0000-1000-8000-00805f9b34fb'), 'bluetooth detects UUID-like names')
assert(bluetooth.isAddressLike('AA:BB:CC:DD:EE:FF'), 'bluetooth detects address-like names')
assertEqual(bluetooth.normalizedAddress('AA:BB_CC-dd-ee-ff'), 'aabbccddeeff', 'bluetooth normalizes BlueZ and PipeWire address formats')
assert(!bluetooth.hasHumanName({ name: 'AA:BB:CC:DD:EE:FF' }), 'bluetooth rejects address-only device labels')
assert(bluetooth.hasHumanName({ deviceName: 'MX Master 3S' }), 'bluetooth accepts human device labels')

const devices = [
  { name: 'Speaker', connected: false, paired: true, address: '2' },
  { name: 'Headphones', connected: true, address: '1' },
  { name: 'Keyboard', connected: false, address: '3' },
  { name: 'AA:BB:CC:DD:EE:FF', connected: true, address: '4' },
  { name: 'Mouse', connected: false, trusted: true, address: '5' }
]

const arrayLikeDevices = {
  0: devices[0],
  1: devices[1],
  length: 2
}
assertDeepEqual(
  bluetooth.toArray(arrayLikeDevices).map(bluetooth.deviceLabel),
  ['Speaker', 'Headphones'],
  'bluetooth converts Quickshell QObjectList-style values into arrays'
)

const lists = bluetooth.deviceLists(devices)
assertDeepEqual(lists.connected.map(bluetooth.deviceLabel), ['Headphones'], 'bluetooth groups connected devices')
assertDeepEqual(lists.known.map(bluetooth.deviceLabel), ['Mouse', 'Speaker'], 'bluetooth groups known devices by label')
assertDeepEqual(lists.discovered.map(bluetooth.deviceLabel), ['Keyboard'], 'bluetooth groups discovered devices')
assertDeepEqual(bluetooth.visibleSections(lists, true), ['connected', 'known', 'discovered'], 'bluetooth shows discovered section while scanning')
assertDeepEqual(bluetooth.visibleSections(lists, false), ['connected', 'known'], 'bluetooth hides discovered section when not scanning')

const arrayLikeLists = bluetooth.deviceLists({
  0: { name: 'Earbuds', connected: true, address: '6' },
  1: { name: 'Trackpad', paired: true, address: '7' },
  2: { name: 'Gamepad', address: '8' },
  length: 3
})
assertDeepEqual(arrayLikeLists.connected.map(bluetooth.deviceLabel), ['Earbuds'], 'bluetooth groups connected devices from array-like values')
assertDeepEqual(arrayLikeLists.known.map(bluetooth.deviceLabel), ['Trackpad'], 'bluetooth groups known devices from array-like values')
assertDeepEqual(arrayLikeLists.discovered.map(bluetooth.deviceLabel), ['Gamepad'], 'bluetooth groups discovered devices from array-like values')

assertDeepEqual(
  bluetooth.deviceRow({ name: 'Deadbeef', address: '1', connected: false }),
  { address: '1', name: 'Deadbeef', deviceName: '', connected: false, state: -1, batteryAvailable: false, battery: 0, pairing: false },
  'bluetooth projects device rows with primitives only'
)
assertEqual(
  bluetooth.deviceLabel(bluetooth.deviceRow({ name: 'Generic', deviceName: 'MX Master 3S', address: '2', connected: true })),
  'MX Master 3S',
  'bluetooth keeps deviceName in row projections so labels survive QObject-free rows'
)

// The device list is a ListModel the panel patches in place. Rebuilding it --
// or handing a ListView a fresh JS array, which is the same reset -- puts the
// viewport back at the top, and discovery rebuilds the rows every few seconds,
// so a list being read mid-scroll kept jumping away under the pointer.
assert(/model: scrollModel/.test(panelSource), 'bluetooth backs the device list with a ListModel it owns')
assert(!/model: root\.scrollRows/.test(panelSource), 'bluetooth never assigns the rebuilt rows to the view as a whole model')
assert(/onScrollEntriesChanged: syncScrollModel\(\)/.test(panelSource), 'bluetooth patches the device list when the rows are rebuilt')

// A view bumps its own currentIndex for every row inserted at or before it,
// and that write does not re-run the binding that fed it, so an index read
// back off the view drifts one row further from the cursor per discovered
// device -- and the scroll-into-view lands on a row nobody is on.
assert(
  /function keepCurrentVisible\(\) \{\s*\n\s*if \(root\.scrollRowIndex >= 0\)\s*\n\s*positionViewAtIndex\(root\.scrollRowIndex, ListView\.Contain\)/.test(panelSource),
  'bluetooth scrolls to the cursor the panel owns, not to the index the view keeps'
)
assert(!/currentIndex: root\.scrollRowIndex/.test(panelSource), 'bluetooth never feeds the cursor through the view\'s own current index')

const scrollRows = (addresses, section) => addresses.map((address, index) => ({
  dev: bluetooth.deviceRow({ name: 'dev' + address, address: address }),
  section: section || 'known',
  indexInSection: index
}))

const knownThenDiscovered = scrollRows(['1', '2'], 'known').concat(scrollRows(['3'], 'discovered'))
assertDeepEqual(
  bluetooth.scrollEntries(knownThenDiscovered).map(entry => entry.sectionTitle),
  ['PAIRED', '', 'AVAILABLE'],
  'bluetooth titles the first row of each section only'
)
assertDeepEqual(
  bluetooth.scrollEntries(knownThenDiscovered).map(entry => entry.key),
  ['known/1', 'known/2', 'discovered/3'],
  'bluetooth keys rows by section and address so a device changing section is a new row'
)

const settled = bluetooth.scrollEntries(scrollRows(['1', '2', '3']))
assertDeepEqual(
  bluetooth.scrollModelOps(settled, settled),
  [],
  'bluetooth touches nothing when a rebuild turns up the same devices'
)

const withNewDevice = bluetooth.scrollEntries(scrollRows(['1', '4', '2', '3']))
assertDeepEqual(
  bluetooth.scrollModelOps(settled, withNewDevice).filter(op => op.op !== 'set').map(op => op.op + ':' + op.index),
  ['insert:1'],
  'bluetooth inserts a discovered device without rebuilding the rows around it'
)

assertDeepEqual(
  bluetooth.scrollModelOps(settled, bluetooth.scrollEntries(scrollRows(['1']))).map(op => `${op.op}:${op.index}:${op.count}`),
  ['remove:1:2'],
  'bluetooth drops timed-out devices off the end of the list'
)

const reordered = bluetooth.scrollModelOps(settled, bluetooth.scrollEntries(scrollRows(['3', '1', '2'])))
assertDeepEqual(
  reordered.filter(op => op.op === 'move').map(op => `${op.from}->${op.to}`),
  ['2->0'],
  'bluetooth moves a re-sorted device instead of replacing the list'
)

const charged = bluetooth.scrollEntries(scrollRows(['1', '2', '3']))
charged[1].battery = 0.75
assertDeepEqual(
  bluetooth.scrollModelOps(settled, charged).map(op => `${op.op}:${op.index}`),
  ['set:1'],
  'bluetooth updates only the row whose device changed'
)

assertDeepEqual(
  bluetooth.scrollEntrySnapshot({ key: 'known/1', extra: 'ignored' }).key,
  'known/1',
  'bluetooth snapshots list rows by role and ignores anything else on the object'
)
assertEqual(
  bluetooth.scrollEntrySnapshot({}).battery,
  undefined,
  'bluetooth snapshots a role the model never set as undefined rather than inventing a value'
)

// ListModel.insert/move/set/remove, in JS. Asserting on the op list alone
// lets a diff that emits plausible-looking ops pass; replaying them is what
// proves the list the panel ends up showing is the list it wanted.
const applyOps = (current, ops) => {
  const rows = current.slice()
  for (const op of ops) {
    if (op.op === 'insert') rows.splice(op.index, 0, op.entry)
    else if (op.op === 'move') rows.splice(op.to, 0, rows.splice(op.from, 1)[0])
    else if (op.op === 'set') rows[op.index] = op.entry
    else if (op.op === 'remove') rows.splice(op.index, op.count)
    else fail(`bluetooth emits only list model operations (got ${op.op})`)
  }
  return rows
}

const replays = [
  ['an unchanged list', ['1', '2', '3'], ['1', '2', '3']],
  ['a device appearing', ['1', '2'], ['1', '3', '2']],
  ['a device timing out', ['1', '2', '3'], ['1', '3']],
  ['every device timing out at once', ['1', '2', '3'], []],
  ['the first devices of a scan', [], ['1', '2', '3']],
  ['a re-sort', ['1', '2', '3'], ['3', '2', '1']],
  ['a re-sort that also gains and loses devices', ['1', '2', '3', '4'], ['5', '3', '1', '6']],
  ['a list replaced wholesale', ['1', '2', '3'], ['7', '8', '9']]
]

for (const [description, before, after] of replays) {
  const from = bluetooth.scrollEntries(scrollRows(before))
  const to = bluetooth.scrollEntries(scrollRows(after))
  assertDeepEqual(
    applyOps(from, bluetooth.scrollModelOps(from, to)),
    to,
    `bluetooth patches the list to exactly what it wants through ${description}`
  )
}

// Producing the right list is not enough: an insert plus a remove lands the
// same rows as a move while destroying and rebuilding that row's delegate,
// which is the thing this list model exists to avoid. BlueZ reports a device
// before its alias often enough that a late label re-sorts it the length of
// the list.
const beforeResort = bluetooth.scrollEntries(scrollRows(['b', 'c', 'd', 'e', 'f', 'g', 'a']))
const afterResort = bluetooth.scrollEntries(scrollRows(['a', 'b', 'c', 'd', 'e', 'f', 'g']))
const resortOps = bluetooth.scrollModelOps(beforeResort, afterResort)
assertDeepEqual(
  applyOps(beforeResort, resortOps),
  afterResort,
  'bluetooth patches the list to exactly what it wants when a late alias re-sorts a device'
)
assertDeepEqual(
  resortOps.filter(op => op.op !== 'set').map(op => `${op.op}:${op.from}->${op.to}`),
  ['move:6->0'],
  'bluetooth moves a re-sorted device the length of the list rather than rebuilding its row'
)
assertEqual(
  bluetooth.scrollModelOps(beforeResort, afterResort).filter(op => op.op === 'insert' || op.op === 'remove').length,
  0,
  'bluetooth never inserts or removes a row when the same devices are merely re-sorted'
)

// A role that is not a finite number would make a row compare unequal to
// itself, and the diff would rewrite it on every rebuild forever.
const unreadable = bluetooth.scrollEntries([{
  dev: { address: '1', name: 'Speaker', state: NaN, battery: 'unknown' },
  section: 'known',
  indexInSection: 0
}])
assertEqual(unreadable[0].devState, -1, 'bluetooth falls back to no connection state when the state does not read as a number')
assertEqual(unreadable[0].battery, 0, 'bluetooth falls back to an empty battery when the reading does not read as a number')
assert(bluetooth.sameScrollEntry(unreadable[0], unreadable[0]), 'bluetooth never builds a row that compares unequal to itself')
assertDeepEqual(
  bluetooth.scrollModelOps(unreadable, unreadable),
  [],
  'bluetooth stops rewriting a row whose device reports something unreadable'
)
assertEqual(bluetooth.finiteNumber('', -1), -1, 'bluetooth reads an empty string as no value rather than as zero')
assertEqual(bluetooth.finiteNumber(0.8, 0), 0.8, 'bluetooth keeps a real battery reading')

// A device can carry a human name and no address at all, which keys two rows
// alike. The diff has to land on the list it was handed anyway rather than let
// a later row match a twin that is already placed.
const twins = [
  { name: 'Speaker', address: '' },
  { name: 'Mouse', address: 'a' },
  { name: 'Keyboard', address: '' }
].map((device, index) => ({ dev: bluetooth.deviceRow(device), section: 'known', indexInSection: index }))
const scanned = bluetooth.scrollEntries(twins)
assertDeepEqual(
  applyOps([], bluetooth.scrollModelOps([], scanned)),
  scanned,
  'bluetooth patches the list to exactly what it wants when rows key alike'
)
assertDeepEqual(
  applyOps(scanned, bluetooth.scrollModelOps(scanned, bluetooth.scrollEntries(twins.slice(1)))),
  bluetooth.scrollEntries(twins.slice(1)),
  'bluetooth drops the right one of two rows that key alike'
)

// Sections are the other half of the key: a device connecting leaves the
// paired list for the connected one, and the row it left has to go.
const paired = bluetooth.scrollEntries(scrollRows(['1', '2'], 'known'))
const scanning = bluetooth.scrollEntries(
  scrollRows(['2'], 'known').concat(scrollRows(['1'], 'discovered'))
)
assertDeepEqual(
  applyOps(paired, bluetooth.scrollModelOps(paired, scanning)),
  scanning,
  'bluetooth patches the list to exactly what it wants when a device changes section'
)

assertDeepEqual(
  bluetooth.withPendingAction({ a: 'connecting' }, 'b', 'forgetting'),
  { a: 'connecting', b: 'forgetting' },
  'bluetooth adds pending actions immutably'
)
assertDeepEqual(bluetooth.withPendingAction({ a: 'connecting' }, 'a', ''), {}, 'bluetooth clears pending actions immutably')

const bluetoothSink = {
  isSink: true,
  isStream: false,
  ready: true,
  name: 'bluez_output.AA_BB_CC_DD_EE_FF.1',
  properties: {
    'device.product.name': 'JBL Go 3'
  }
}
assert(
  bluetooth.bluetoothSinkMatchesDevice(bluetoothSink, { address: 'AA:BB:CC:DD:EE:FF', name: 'JBL Go 3' }),
  'bluetooth matches audio sinks by device address'
)
assert(
  bluetooth.bluetoothSinkMatchesDevice(
    {
      isSink: true,
      isStream: false,
      ready: true,
      name: 'alsa_output.usb-speaker',
      properties: { 'device.product.name': 'JBL Go 3' }
    },
    { address: '11:22:33:44:55:66', name: 'JBL Go 3' }
  ),
  'bluetooth matches audio sinks by human device label when address is unavailable'
)
assert(
  !bluetooth.bluetoothSinkMatchesDevice({ isSink: false, isStream: false, ready: true, name: 'bluez_output.AA_BB_CC_DD_EE_FF.1', properties: {} }, { address: 'AA:BB:CC:DD:EE:FF', name: 'JBL Go 3' }),
  'bluetooth ignores non-sink nodes when matching audio outputs'
)
JS

# Turning Bluetooth off is an rfkill soft block, not a bluetoothctl power off,
# because only the block survives a reboot. These mocks stand in for that pair:
# rfkill moves the block, and bluetoothd powers the adapter up once it is gone.
device_tmp=$(mktemp -d)
trap 'rm -rf "$device_tmp"' EXIT

mock_bin="$device_tmp/bin"
mkdir -p "$mock_bin"
export POWERED_FILE="$device_tmp/powered"

cat >"$mock_bin/bluetoothctl" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$BLUETOOTHCTL_LOG"
[[ $1 == "power" && $2 == "on" ]] && echo yes >"$POWERED_FILE"
[[ $1 == "list" ]] &&
  for c in ${MOCK_CONTROLLERS:-AA:BB:CC:DD:EE:FF}; do printf 'Controller %s mock\n' "$c"; done
# Per-controller state where a test set it, the shared file otherwise.
if [[ $1 == "show" ]]; then
  state="$POWERED_FILE"
  [[ -n ${2:-} && -f "$POWERED_FILE.$2" ]] && state="$POWERED_FILE.$2"
  printf '\tPowered: %s\n' "$(cat "$state")"
fi
exit 0
SH

cat >"$mock_bin/rfkill" <<'SH'
#!/bin/bash

printf 'rfkill %s\n' "$*" >>"$BLUETOOTHCTL_LOG"
# Lifting the block is normally all it takes: AutoEnable is left at its default,
# so bluetoothd powers the adapter up on its own. RFKILL_INERT stands in for the
# adapter that was powered down without a block, where it does not.
[[ $1 == "unblock" && -z ${RFKILL_INERT:-} ]] && echo yes >"$POWERED_FILE"
[[ $1 == "block" ]] && echo no >"$POWERED_FILE"
exit 0
SH

chmod +x "$mock_bin/bluetoothctl" "$mock_bin/rfkill"

# $ROOT/bin so omarchy-bluetooth-device resolves the real omarchy-bluetooth-power.
bluetooth_run() {
  local powered="$1"
  shift

  echo "$powered" >"$POWERED_FILE"
  : >"$device_tmp/log"
  PATH="$mock_bin:$ROOT/bin:$PATH" BLUETOOTHCTL_LOG="$device_tmp/log" \
    OMARCHY_BLUETOOTH_POWER_WAIT_SECONDS=0 "$@" ||
    fail "$* exits cleanly with Powered: $powered"
  printf '%s' "$device_tmp/log"
}

bluetooth_power() {
  bluetooth_run "$1" "$ROOT/bin/omarchy-bluetooth-power" "$2"
}

# Off has to be the block. A bluetoothctl power off would read the same until the
# next boot, then quietly come back on.
off_log=$(bluetooth_power yes off)
grep -qx "rfkill block bluetooth" "$off_log" ||
  fail "bluetooth turns off with an rfkill block" "$(cat "$off_log")"
pass "bluetooth turns off with an rfkill block"

grep -q "power off" "$off_log" &&
  fail "bluetooth does not also power the adapter down" "$(cat "$off_log")"
pass "bluetooth does not also power the adapter down"

# Unblocking is enough on its own, so there is nothing left to ask bluetoothctl.
on_log=$(bluetooth_power no on)
grep -qx "rfkill unblock bluetooth" "$on_log" ||
  fail "bluetooth turns on by lifting the block" "$(cat "$on_log")"
pass "bluetooth turns on by lifting the block"

grep -q "power on" "$on_log" &&
  fail "bluetooth leaves the power-on to bluetoothd when the block is lifted" "$(cat "$on_log")"
pass "bluetooth leaves the power-on to bluetoothd when the block is lifted"

# An adapter powered down without a block is one bluetoothd will not pick up.
inert_log=$(RFKILL_INERT=1 bluetooth_power no on)
grep -qx "power on" "$inert_log" ||
  fail "bluetooth powers the adapter on when unblocking does not" "$(cat "$inert_log")"
pass "bluetooth powers the adapter on when unblocking does not"

# The panel switch reads Powered, so that is what toggle has to invert.
toggle_on_log=$(bluetooth_power yes toggle)
grep -qx "rfkill block bluetooth" "$toggle_on_log" ||
  fail "bluetooth toggles a powered adapter off" "$(cat "$toggle_on_log")"
pass "bluetooth toggles a powered adapter off"

toggle_off_log=$(bluetooth_power no toggle)
grep -qx "rfkill unblock bluetooth" "$toggle_off_log" ||
  fail "bluetooth toggles an unpowered adapter on" "$(cat "$toggle_off_log")"
pass "bluetooth toggles an unpowered adapter on"

# The power-on shortcut is the whole point of skipping the stabilization sleep:
# pair/connect from the panel run against an adapter that is already powered.
bluetooth_device_log() {
  bluetooth_run "$1" "$ROOT/bin/omarchy-bluetooth-device" connect AA:BB:CC:DD:EE:FF
}

powered_log=$(bluetooth_device_log yes)
grep -q "rfkill" "$powered_log" &&
  fail "bluetooth skips the power-on delay when the adapter is already powered"
pass "bluetooth skips the power-on delay when the adapter is already powered"

grep -qx "connect AA:BB:CC:DD:EE:FF" "$powered_log" ||
  fail "bluetooth still connects when the adapter is already powered"
pass "bluetooth still connects when the adapter is already powered"

# Connecting to a device while Bluetooth is off has to lift the block first —
# BlueZ refuses to power an adapter up while one is set.
unpowered_log=$(bluetooth_device_log no)
grep -qx "rfkill unblock bluetooth" "$unpowered_log" ||
  fail "bluetooth lifts the block before connecting" "$(cat "$unpowered_log")"
pass "bluetooth lifts the block before connecting"

grep -qx "connect AA:BB:CC:DD:EE:FF" "$unpowered_log" ||
  fail "bluetooth connects once the adapter is up" "$(cat "$unpowered_log")"
pass "bluetooth connects once the adapter is up"

# Blocking hits every radio at once, so the read has to span them too. A bare
# bluetoothctl show reports the default controller and misses a powered dongle.
echo yes >"$POWERED_FILE.11:22:33:44:55:66"
export MOCK_CONTROLLERS="AA:BB:CC:DD:EE:FF 11:22:33:44:55:66"
multi_log=$(bluetooth_power no toggle)
unset MOCK_CONTROLLERS
rm -f "$POWERED_FILE.11:22:33:44:55:66"

grep -qx "rfkill block bluetooth" "$multi_log" ||
  fail "bluetooth counts a secondary controller as on" "$(cat "$multi_log")"
pass "bluetooth counts a secondary controller as on"

# AutoEnable=false was the old attempt at persistence and never worked. Left set,
# it would also keep bluetoothd from powering the adapter up after an unblock.
grep -q 'AutoEnable=false' "$ROOT/install/hardware/bluetooth.sh" &&
  fail "bluetooth install leaves AutoEnable at its default"
pass "bluetooth install leaves AutoEnable at its default"
