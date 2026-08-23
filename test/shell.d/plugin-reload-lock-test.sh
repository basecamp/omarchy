#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const shellQml = fs.readFileSync(path.join(root, 'shell/shell.qml'), 'utf8')

assert(
  /function lockServiceOwned\(\) \{[\s\S]*_services\["omarchy.lock"\]/.test(shellQml),
  'plugin reload can tell when the lock service owns the session lock'
)

// `sessionLock` is an id inside Service.qml, so it is not reachable as a
// property from here; the service exposes lockOwned for exactly this.
assert(
  /function lockServiceOwned\(\) \{[\s\S]*lockInst\.lockOwned/.test(shellQml),
  'lock ownership is read through the property the service exposes'
)

assert(
  /function unloadPluginServices\(\) \{[\s\S]*existingId === "omarchy.lock" && lockServiceOwned\(\)/.test(shellQml),
  'plugin reload does not destroy omarchy.lock while it owns the session lock'
)

assert(
  /function finishPluginReload\(\) \{[\s\S]*!lockServiceOwned\(\) && typeof Qt\.clearComponentCache/.test(shellQml),
  'plugin reload does not clear the QML cache while the lock client is mounted'
)
JS
