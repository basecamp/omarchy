#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

// `omarchy-brightness-display on` skips its dispatch when the display still
// looks lit, so a wake that overtakes an in-flight blank does nothing and the
// blank then takes the panel down behind it, with the blanked flag already
// false and the keyboard monitor disarmed.
assert(
  /if \(!blankProcess\.running && !wakeProcess\.running\) wakeProcess\.running = true/.test(serviceQml),
  'a wake waits for an in-flight blank instead of racing its DPMS off'
)

assert(
  /id: blankProcess[\s\S]*?onExited: if \(!root\.displayBlanked && !wakeProcess\.running\) wakeProcess\.running = true/.test(serviceQml),
  'the blank runs the wake it held back once its own DPMS off has landed'
)
JS
