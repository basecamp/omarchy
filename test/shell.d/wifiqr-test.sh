#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const wifiqr = requireFromRoot('shell/plugins/panels/wifiqr/Model.js')

assertDeepEqual(
  wifiqr.parseQrOutput('meta\twlan0\tWPA\tCafe WiFi\n010\n111\n010\n'),
  { meta: { iface: 'wlan0', security: 'WPA', ssid: 'Cafe WiFi' }, matrix: { rows: ['010', '111', '010'], size: 3 } },
  'wifiqr parses the meta header and a square matrix'
)
assertDeepEqual(
  wifiqr.parseQrOutput('meta\twlan0\tnopass\tTab\tName\n010\n111\n010\n').meta.ssid,
  'Tab\tName',
  'wifiqr keeps tabs inside the SSID field'
)
assertDeepEqual(
  wifiqr.parseQrOutput('010\n111\n010\n'),
  { meta: { iface: '', security: '', ssid: '' }, matrix: { rows: ['010', '111', '010'], size: 3 } },
  'wifiqr tolerates output without a meta header'
)
assertDeepEqual(wifiqr.parseQrOutput('meta\twlan0\tWPA\tCafe\n01\n111\n').matrix, { rows: [], size: 0 }, 'wifiqr rejects ragged QR rows')
assertDeepEqual(wifiqr.parseQrOutput('010\n101\n').matrix, { rows: [], size: 0 }, 'wifiqr rejects a non-square QR matrix')
assertDeepEqual(wifiqr.parseQrOutput('010\n1x1\n010\n').matrix, { rows: [], size: 0 }, 'wifiqr rejects invalid QR modules')
JS
