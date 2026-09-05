#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

const secureHandlerStart = serviceQml.indexOf('onSecureStateChanged:')
const lockHandlerStart = serviceQml.indexOf('onLockStateChanged:', secureHandlerStart)
const secureHandler = serviceQml.slice(secureHandlerStart, lockHandlerStart)
const secureBlockMatch = secureHandler.match(/if \(secure\) \{([\s\S]*?)\n      \}/)
const secureBlock = secureBlockMatch ? secureBlockMatch[1] : ''

assert(
  secureBlock.includes('lockView.forcePasswordFocus()'),
  'the password field regains focus when the compositor secures the lock surface'
)
JS
