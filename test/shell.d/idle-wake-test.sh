#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
// Comments are allowed to name the commands; only code that runs them counts.
const readCode = (file) => fs.readFileSync(file, 'utf8').replace(/^\s*\/\/.*$/gm, '')
const idleQml = readCode(path.join(root, 'shell/plugins/services/idle/Service.qml'))

// lockSystem ends the cycle, so cancelIdleCycle only ever runs for a cycle
// that never locked -- and nothing was blanked during one of those.
assert(
  /function lockSystem\([^)]*\) \{[^}]*root\.idledThisCycle = false/.test(idleQml),
  'locking ends the idle cycle'
)

// omarchy-system-wake restores the keyboard backlight from brightnessctl's
// saved level. With no blank to undo, that only overwrote whatever the keyboard
// was showing with a stale level (#7650), so the cancel path must not run it.
assert(
  !/omarchy-system-wake/.test(idleQml),
  'cancelling an idle cycle does not run omarchy-system-wake'
)

// The lock service is the only shell plugin that blanks, so it has to stay the
// only one that wakes: a wake with no matching blank restores a stale level.
const wakers = []
const walk = (dir) => {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) walk(full)
    else if (entry.name.endsWith('.qml') && /omarchy-system-wake|omarchy-brightness-keyboard restore/.test(readCode(full))) {
      wakers.push(path.relative(root, full))
    }
  }
}
walk(path.join(root, 'shell/plugins'))
assertDeepEqual(wakers, ['shell/plugins/lock/Service.qml'], 'only the lock service wakes the keyboard backlight')
JS
