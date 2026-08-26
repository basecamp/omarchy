#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const panel = fs.readFileSync(path.join(root, 'shell/plugins/panels/disk-speedtest/Panel.qml'), 'utf8')
const script = fs.readFileSync(path.join(root, 'bin/omarchy-disk-speedtest'), 'utf8')

assert(panel.includes('parts[0] === "write" || parts[0] === "stage"'),
  'disk speedtest panel treats staging samples as write-dial input')
assert(panel.includes('root.phase === "write" || root.phase === "stage"'),
  'disk speedtest panel keeps the write dial live during staging')
assert(panel.includes('phase = ""'),
  'disk speedtest panel starts with no phase so the read dial is not live at 0')
assert(script.includes('echo "stage '),
  'disk speedtest emits stage rates while it writes the read-test files')
JS
