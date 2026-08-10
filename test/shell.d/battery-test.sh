#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const battery = requireFromRoot('shell/plugins/services/battery/BatteryModel.js')
const discharging = 1

assertEqual(battery.batteryPercentage({ isPresent: true, percentage: 0.126 }), 13, 'battery rounds display percentage')
assertEqual(battery.batteryPercentage({ isPresent: false, percentage: 0.5 }), -1, 'battery reports missing battery')
assert(battery.isDischarging({ isPresent: true, state: discharging }, true, discharging), 'battery detects discharging state')
assert(!battery.isDischarging({ isPresent: true, state: discharging }, false, discharging), 'battery requires on-battery state')

assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: true, percentage: 0.08, state: discharging }, true, discharging, 10, false, true),
  { level: 8, notify: true, dismiss: false, notifiedLowBattery: true, dismissedLowBattery: false },
  'battery warns once under threshold'
)
assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: true, percentage: 0.08, state: discharging }, true, discharging, 10, true, false),
  { level: 8, notify: false, dismiss: false, notifiedLowBattery: true, dismissedLowBattery: false },
  'battery keeps low-battery notified state'
)
assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: true, percentage: 0.4, state: discharging }, true, discharging, 10, true, false),
  { level: 40, notify: false, dismiss: true, notifiedLowBattery: false, dismissedLowBattery: true },
  'battery clears notified state after recovery'
)
assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: true, percentage: 0.08, state: discharging }, false, discharging, 10, true, false),
  { level: 8, notify: false, dismiss: true, notifiedLowBattery: false, dismissedLowBattery: true },
  'battery dismisses the warning once charging'
)
assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: true, percentage: 0.4, state: discharging }, true, discharging, 10, false, false),
  { level: 40, notify: false, dismiss: true, notifiedLowBattery: false, dismissedLowBattery: true },
  'battery clears a warning restored from a previous shell process'
)
assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: true, percentage: 0.4, state: discharging }, true, discharging, 10, false, true),
  { level: 40, notify: false, dismiss: false, notifiedLowBattery: false, dismissedLowBattery: true },
  'battery dismisses only once per recovery'
)
assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: false, percentage: 0.5 }, false, discharging, 10, true, false),
  { level: -1, notify: false, dismiss: true, notifiedLowBattery: false, dismissedLowBattery: true },
  'battery dismisses the warning when the battery disappears'
)
JS

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
cat >"$tmp_dir/bin/omarchy-notification-dismiss" <<STUB
#!/bin/bash

printf '%s\n' "\$1" >"$tmp_dir/dismissed"
STUB
chmod +x "$tmp_dir/bin/omarchy-notification-dismiss"

PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-low" --dismiss

grep -Fx "Time to recharge!" "$tmp_dir/dismissed" >/dev/null ||
  fail "battery low dismisses the recharge notification"

pass "battery low dismisses the recharge notification"
