#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')
const shellDefaults = JSON.parse(fs.readFileSync(path.join(root, 'config/omarchy/shell.json'), 'utf8'))

assert(
  /idleConfig\.lockBlank/.test(serviceQml),
  'the blank delay reads idle.lockBlank from the shell config'
)

assert(
  /interval:\s*root\.blankTimeoutSeconds\s*\*\s*1000/.test(serviceQml),
  'the blank timer takes its interval from the configured seconds'
)

assert(
  /defaultBlankSeconds:\s*5\b/.test(serviceQml),
  'the QML fallback keeps the 5-second default'
)

assertEqual(shellDefaults.idle.lockBlank, 5, 'the shipped default keeps the 5-second blank')
JS
