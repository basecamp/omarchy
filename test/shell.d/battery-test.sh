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
assert(!battery.shouldDismissLowBatteryWarning({ ready: false }, false), 'battery keeps warnings until UPower is ready')
assert(battery.shouldDismissLowBatteryWarning({ ready: true }, false), 'battery dismisses warnings on AC')
assert(!battery.shouldDismissLowBatteryWarning({ ready: true }, true), 'battery keeps warnings while on battery')
assertDeepEqual(
  battery.shouldWarnLowBattery({ ready: false }, false, discharging, 10, true),
  { level: -1, notify: false, notifiedLowBattery: true },
  'battery preserves warning state until UPower is ready'
)

assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: true, percentage: 0.08, state: discharging }, true, discharging, 10, false),
  { level: 8, notify: true, notifiedLowBattery: true },
  'battery warns once under threshold'
)
assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: true, percentage: 0.08, state: discharging }, true, discharging, 10, true),
  { level: 8, notify: false, notifiedLowBattery: true },
  'battery keeps low-battery notified state'
)
assertDeepEqual(
  battery.shouldWarnLowBattery({ isPresent: true, percentage: 0.4, state: discharging }, true, discharging, 10, true),
  { level: 40, notify: false, notifiedLowBattery: false },
  'battery clears notified state after recovery'
)
JS

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
cat >"$tmp_dir/bin/omarchy-notification-send" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >"$OMARCHY_TEST_BATTERY_NOTIFICATION"
STUB
cat >"$tmp_dir/bin/omarchy-hook" <<'STUB'
#!/bin/bash
:
STUB
chmod +x "$tmp_dir/bin/omarchy-notification-send" "$tmp_dir/bin/omarchy-hook"

OMARCHY_TEST_BATTERY_NOTIFICATION="$tmp_dir/notification" PATH="$tmp_dir/bin:$PATH" \
  "$ROOT/bin/omarchy-battery-low" 8

mapfile -t notification_args <"$tmp_dir/notification"
[[ ${notification_args[0]} == "--app-name" ]] || fail "low battery warning passes app-name flag"
[[ ${notification_args[1]} == "omarchy-battery" ]] || fail "low battery warning uses a stable app identity"
pass "low battery warning uses a stable app identity"
