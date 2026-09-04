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
  bluetooth.deviceRow({ name: 'Generic', deviceName: 'MX Master 3S', address: '2', connected: true }).deviceName,
  'MX Master 3S',
  'bluetooth keeps deviceName in row projections so the reported name survives QObject-free rows'
)

// BlueZ reports Alias (device.name) as a copy of Name until a user sets one,
// so the alias is the display name and deviceName is only the fallback.
assertEqual(
  bluetooth.deviceLabel(bluetooth.deviceRow({ name: 'Comfy Mouse', deviceName: 'MX Master 3S', address: '2', connected: true })),
  'Comfy Mouse',
  'bluetooth labels a device by its BlueZ alias so a renamed device shows the custom name'
)

// Writing an empty alias is how a custom name is dropped, and quickshell holds
// that empty value locally until BlueZ echoes the device name back.
assertEqual(
  bluetooth.deviceLabel({ name: '', deviceName: 'MX Master 3S' }),
  'MX Master 3S',
  'bluetooth falls back to the reported name while a cleared alias is in flight'
)
assertEqual(bluetooth.deviceRealName({ name: 'Comfy Mouse', deviceName: 'MX Master 3S' }), 'MX Master 3S', 'bluetooth can still name the device behind an alias')

assert(bluetooth.hasAlias({ name: 'Comfy Mouse', deviceName: 'MX Master 3S' }), 'bluetooth sees a user alias when it differs from the device name')
// BlueZ answers a cleared alias with a copy of Name, so an alias equal to the
// name is indistinguishable from none — and clearing it would be a no-op write
// that BlueZ reports nothing back for.
assert(!bluetooth.hasAlias({ name: 'MX Master 3S', deviceName: 'MX Master 3S' }), 'bluetooth reads BlueZ echoing Name back as Alias as no alias at all')
assert(!bluetooth.hasAlias({ name: '', deviceName: 'MX Master 3S' }), 'bluetooth reads the empty alias of an in-flight reset as no alias')
assert(bluetooth.hasAlias({ name: 'Tile Tracker', deviceName: '' }), 'bluetooth sees an alias on a device that reports no name of its own')
assert(!bluetooth.hasAlias(null), 'bluetooth tolerates a missing device when checking for an alias')

// hasHumanName gates every list, and after the alias takes precedence it gates
// on a string the user picked. A MAC typed as a name must not drop the row out
// of the panel that is the only place to change it back.
assert(bluetooth.hasHumanName({ name: 'AA:BB:CC:DD:EE:FF', deviceName: 'MX Master 3S' }), 'bluetooth keeps listing a device whose alias looks like an address')
assert(bluetooth.hasHumanName({ name: 'Tile Tracker', deviceName: '' }), 'bluetooth lists an aliased device that reports no name of its own')
assert(!bluetooth.hasHumanName({ name: 'AA-BB-CC-DD-EE-FF', deviceName: '' }), "bluetooth still filters BlueZ's address-derived alias for a nameless device")

// A device that reports no name of its own, renamed to something address-shaped,
// would otherwise vanish from the only panel that could rename it back.
assertEqual(
  bluetooth.deviceLists([{ address: '1', name: 'AA:BB:CC:DD:EE:FF', deviceName: '', paired: true }]).known.length,
  1,
  'bluetooth keeps a remembered device listed whatever it ends up called'
)
assertEqual(
  bluetooth.deviceLists([{ address: '1', name: 'AA:BB:CC:DD:EE:FF', deviceName: '' }]).discovered.length,
  0,
  'bluetooth still keeps address-named junk out of a scan'
)

assertDeepEqual(
  bluetooth.deviceLists([
    { name: 'Aardvark', deviceName: 'Zeta Speaker', paired: true, address: '1' },
    { name: 'Zulu', deviceName: 'Alpha Buds', paired: true, address: '2' }
  ]).known.map(bluetooth.deviceLabel),
  ['Aardvark', 'Zulu'],
  'bluetooth sorts remembered devices by the name the user sees'
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

// The panel walks every sink for an address before it guesses at names, so the
// two criteria have to be separable. Testing each sink against both in turn
// would let a name guess on an earlier node beat the addressed node below it.
const addressedLast = [
  { isSink: true, isStream: false, ready: true, name: 'alsa_output.hifi__speaker__sink', properties: {} },
  { isSink: true, isStream: false, ready: true, name: 'bluez_output.AA_BB_CC_DD_EE_FF.1', properties: { 'api.bluez5.address': 'AA:BB:CC:DD:EE:FF' } }
]
// A device whose own reported name is a substring of an unrelated sink: plenty
// of speakers report themselves as "Speaker".
const speaker = { address: 'AA:BB:CC:DD:EE:FF', deviceName: 'Speaker' }
assertEqual(
  addressedLast.filter(function(n) { return bluetooth.bluetoothSinkMatchesAddress(n, speaker) }).length,
  1,
  'bluetooth matches exactly one sink on the device address'
)
assert(
  bluetooth.bluetoothSinkMatchesName(addressedLast[0], speaker),
  'bluetooth would match the earlier unrelated sink by name, which is why the address pass runs first'
)
assert(
  bluetooth.bluetoothSinkMatchesAddress(addressedLast[1], speaker),
  'bluetooth finds the addressed sink even though it sorts after the name match'
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
    { address: '11:22:33:44:55:66', name: 'Kitchen Speaker', deviceName: 'JBL Go 3' }
  ),
  'bluetooth still matches a renamed device to its sink by the name PipeWire knows it under'
)
// A short alias as an unconstrained substring matches unrelated nodes: "Pro" is
// in pro-output-3, "Car" is in alsa_card. Matching only the reported name keeps
// a renamed headset from stealing an HDMI or USB output.
assert(
  !bluetooth.bluetoothSinkMatchesDevice(
    { isSink: true, isStream: false, ready: true, name: 'alsa_output.pci-0000_c1_00.1.pro-output-3', properties: {} },
    { address: 'AA:BB:CC:DD:EE:FF', name: 'Pro', deviceName: 'AirPods Pro' }
  ),
  'bluetooth does not match an unrelated sink on a short user alias'
)
assert(
  !bluetooth.bluetoothSinkMatchesDevice(
    { isSink: true, isStream: false, ready: true, name: 'alsa_output.hifi__speaker__sink', properties: { 'device.name': 'alsa_card.pci-0000_c1_00.6' } },
    { address: 'AA:BB:CC:DD:EE:FF', name: 'Car', deviceName: 'AirPods Pro' }
  ),
  'bluetooth does not match a sink because an alias is a substring of its card name'
)

// What follows pins the decisions whose violation is silent — a rename that
// still looks right on screen. Anything that would visibly stop working on the
// first keypress is left to the eye, not asserted against the source.
//
// Renaming is a plain write of BlueZ's Alias on the live device object. Unlike
// pair/connect/forget there is nothing to sequence, so it must not grow a
// helper in bin/ — the mirror of the adapter.enabled assertion above.
assert(!/deviceCommand\("rename"|execDetached\(\[[^\]]*rename/.test(panelSource), 'bluetooth renames over D-Bus instead of shelling out')

// BlueZ answers a write of "" with Alias = Name, which is not a change when
// Alias already equals Name — nothing comes back, and quickshell's optimistic
// local value would sit empty. So the clear only goes out when there is one.
assert(/if \(Model\.hasAlias\(device\)\) device\.name = ""/.test(panelSource), 'bluetooth only clears an alias that exists')

const nameField = panelSource.match(/id: nameField[\s\S]*?\n {6}\}/)
assert(nameField && /text: row\.isRenameOpen \? root\.renameText : ""/.test(nameField[0]), 'bluetooth keeps the rename draft on the panel so a rebuilt delegate does not lose it')
assert(nameField && /Component\.onCompleted: if \(visible\) Qt\.callLater\(forceActiveFocus\)/.test(nameField[0]), 'bluetooth takes focus back when discovery rebuilds the row mid-edit')

// The row's click handler covers the whole row, editor included.
assert(/id: rowMouse[\s\S]{0,400}enabled: !row\.isRenameOpen/.test(panelSource), 'bluetooth stops a row click from connecting the device being renamed')

// BlueZ persists an alias only for a device it stores, and a renameAddress left
// pointing at a vanished row would leave the catcher blocked and the panel deaf.
assert(/renameAvailable: forgetAvailable/.test(panelSource), 'bluetooth offers renaming exactly where it offers forgetting')
// Hung off deviceGroups rather than devices: the latter only re-evaluates when
// the set of device objects changes, so an unpair that leaves the object in
// place would strand renameAddress and block the key catcher for good.
assert(/function cancelRenameIfGone\(\)/.test(panelSource) && /onDeviceGroupsChanged: cancelRenameIfGone\(\)/.test(panelSource), 'bluetooth closes the editor when the device it points at stops being remembered')
assert(/function startRename\(device\)[\s\S]*?pendingAction\(device\.address\) === "forgetting"\) return/.test(panelSource), 'bluetooth refuses to open an editor on a device already being forgotten')
assert(/onOpenedChanged: \{[\s\S]{0,200}?cancelRename\(\)/.test(panelSource), 'bluetooth drops an open rename editor when the panel closes')

// Every action a row offers is reachable from the keyboard: h/l walk the row,
// its pencil, and its forget button rather than toggling one action slot.
assert(/order\[next\] === "rename" && !focusedRowCanRename/.test(panelSource), 'bluetooth steps the cursor over a pencil the row is not showing')

// A panel opens with cursorActive false and selectedIndex 0, so an unguarded
// 'r' opens an editor on a row the user never picked and cannot see picked.
assert(/if \(t === "r" \|\| t === "R"\) \{ if \(root\.cursorActive\) root\.startRenameSelected\(\) \}/.test(panelSource), "bluetooth ignores 'r' until the cursor is on screen")

// The separated criteria above only help if the panel walks the sinks twice:
// one loop testing both would still let a name guess on an earlier node beat
// the addressed node below it, and audio would simply come out of the wrong
// speaker. The `} for (` between them is what pins the second pass.
const audioSinkLookup = panelSource.match(/function bluetoothAudioSink\(device\)[\s\S]*?\n {2}\}/)
assert(audioSinkLookup, 'bluetooth has the audio sink lookup')
assert(/MatchesAddress[\s\S]*?\}\s*for \([\s\S]*?MatchesName/.test(audioSinkLookup[0]), 'bluetooth searches every sink for the address before it falls back to names')
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
