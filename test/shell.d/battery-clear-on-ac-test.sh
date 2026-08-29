#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/services/battery/Service.qml'), 'utf8')

assert(
  /function clearLowBatteryWarning\(\)/.test(serviceQml),
  'battery service can dismiss the low-battery toast'
)

assert(
  /omarchy-notification-dismiss[\s\S]*Time to recharge!/.test(serviceQml),
  'battery service dismisses by the Time to recharge! summary'
)

assert(
  /else if \(wasNotified && !state\.notifiedLowBattery\) clearLowBatteryWarning\(\)/.test(serviceQml),
  'battery service clears the toast when leaving the low-discharging state'
)
JS
