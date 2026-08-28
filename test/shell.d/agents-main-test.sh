#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const mainSource = fs.readFileSync(root + '/shell/plugins/agents/Main.qml', 'utf8')

assert(/type:\s*raw\.type\s*\?/.test(mainSource), 'agents main normalizes balance type')
JS
