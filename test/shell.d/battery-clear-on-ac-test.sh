#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

service_qml="$ROOT/shell/plugins/services/battery/Service.qml"

grep -q 'function clearLowBatteryWarning()' "$service_qml" || fail "battery service can dismiss the low-battery toast"
grep -q 'Time to recharge!' "$service_qml" || fail "battery service dismisses by the Time to recharge! summary"
grep -q 'omarchy-notification-dismiss' "$service_qml" || fail "battery service uses omarchy-notification-dismiss"
grep -q 'clearLowBatteryWarning()' "$service_qml" || fail "battery service calls clear when leaving low-discharging"

pass "battery service clears the low-battery toast on AC"
