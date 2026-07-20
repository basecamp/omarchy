#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const utilQml = fs.readFileSync(path.join(root, 'shell/Commons/Util.qml'), 'utf8')

assert(
  /function execDetached\(command\)[\s\S]*Quickshell\.execDetached\(\["bash", "-lc", command\]\)/.test(utilQml),
  'detached command helper uses a login shell'
)

JS
