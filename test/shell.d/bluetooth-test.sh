#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const bluetooth = requireFromRoot('shell/plugins/bluetooth/BluetoothModel.js')

assert(bluetooth.isUuidLike('0000110b-0000-1000-8000-00805f9b34fb'), 'bluetooth detects UUID-like names')
assert(bluetooth.isAddressLike('AA:BB:CC:DD:EE:FF'), 'bluetooth detects address-like names')
assert(!bluetooth.hasHumanName({ name: 'AA:BB:CC:DD:EE:FF' }), 'bluetooth rejects address-only device labels')
assert(bluetooth.hasHumanName({ deviceName: 'MX Master 3S' }), 'bluetooth accepts human device labels')

const devices = [
  { name: 'Speaker', connected: false, paired: true, address: '2' },
  { name: 'Headphones', connected: true, address: '1' },
  { name: 'Keyboard', connected: false, address: '3' },
  { name: 'AA:BB:CC:DD:EE:FF', connected: true, address: '4' },
  { name: 'Mouse', connected: false, trusted: true, address: '5' }
]

const lists = bluetooth.deviceLists(devices)
assertDeepEqual(lists.connected.map(bluetooth.deviceLabel), ['Headphones'], 'bluetooth groups connected devices')
assertDeepEqual(lists.known.map(bluetooth.deviceLabel), ['Mouse', 'Speaker'], 'bluetooth groups known devices by label')
assertDeepEqual(lists.discovered.map(bluetooth.deviceLabel), ['Keyboard'], 'bluetooth groups discovered devices')
assertDeepEqual(bluetooth.visibleSections(lists, true), ['connected', 'known', 'discovered'], 'bluetooth shows discovered section while scanning')
assertDeepEqual(bluetooth.visibleSections(lists, false), ['connected', 'known'], 'bluetooth hides discovered section when not scanning')

assertDeepEqual(
  bluetooth.withPendingAction({ a: 'connecting' }, 'b', 'forgetting'),
  { a: 'connecting', b: 'forgetting' },
  'bluetooth adds pending actions immutably'
)
assertDeepEqual(bluetooth.withPendingAction({ a: 'connecting' }, 'a', ''), {}, 'bluetooth clears pending actions immutably')
JS
