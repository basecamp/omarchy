#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

// Quickshell creates one WlSessionLockSurface per output from the lock's
// `surface` Component. A single live surface instance shared across monitors
// reparents the same QQuickItem tree onto every lock window and crashes Qt
// ("Cannot use same item on different windows") on multi-monitor idle lock.
assert(
  /Component\s*\{\s*id:\s*lockSurfaceComponent[\s\S]*WlSessionLockSurface\s*\{/.test(serviceQml),
  'the lock surface is defined as a Component so each output gets its own tree'
)

assert(
  /WlSessionLock\s*\{[\s\S]*surface:\s*lockSurfaceComponent/.test(serviceQml),
  'WlSessionLock uses the per-screen surface Component'
)

// A nested live surface (not wrapped in Component) is the failing pattern.
assert(
  !/WlSessionLock\s*\{[\s\S]*?WlSessionLockSurface\s*\{[\s\S]*?id:\s*lockSurface/.test(serviceQml),
  'WlSessionLock does not keep a single live lockSurface instance as a child'
)

// Each surface still hosts a LockView bound to the shared lock state so
// password entry mirrors across screens without sharing QQuickItems.
assert(
  /id:\s*lockSurfaceComponent[\s\S]*LockView\s*\{[\s\S]*passwordText:\s*root\.enteredPassword/.test(serviceQml),
  'each surface LockView still mirrors password entry through enteredPassword'
)

assert(
  /id:\s*lockSurfaceComponent[\s\S]*onPasswordTextEdited:/.test(serviceQml),
  'each surface LockView still writes password edits back to the lock service'
)
JS
