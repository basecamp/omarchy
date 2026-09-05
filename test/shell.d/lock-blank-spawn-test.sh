#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

// A Quickshell Process is `running` while its child exists, so reusing one for
// blank and wake turns a single child that never exits into a display that
// never blanks -- or, through runWake(), never comes back -- until the shell
// restarts. Nothing times it out, and the lock IPC cannot see it happen.
assert(
  !/id: (blank|wake)Process/.test(serviceQml),
  'blank and wake do not run through a Process reused across invocations'
)

assert(
  /function runBlank\(\) \{[\s\S]*?Quickshell\.execDetached\(\["bash", "-c", "omarchy-brightness-keyboard off; omarchy-brightness-display off"\]\)/.test(serviceQml),
  'the blank spawns statelessly'
)

assert(
  /function forceWake\(\) \{[\s\S]*?Quickshell\.execDetached\(\["bash", "-c", "omarchy-system-wake"\]\)/.test(serviceQml),
  'the wake spawns statelessly'
)

// Pointer motion calls runWake() at input rate, so dropping the old Process
// guard without a replacement forks a shell per motion event. A Timer rather
// than wall-clock arithmetic, so a clock stepping backwards cannot suppress it.
assert(
  /function runWake\(\) \{\s*if \(!wakeCoalesceTimer\.running\) forceWake\(\)/.test(serviceQml),
  'the wake coalesces on a timer instead of on a process it can no longer see'
)

assert(
  /function forceWake\(\) \{\s*wakeCoalesceTimer\.restart\(\)/.test(serviceQml),
  'every wake opens the coalescing window'
)

// The lock surface is gone by the time these run, so nothing is left to ask
// again for a wake the coalescing window swallowed.
assert(
  /function finishUnlock\(\)[\s\S]*?logEvent\("unlocked"\)\s*forceWake\(\)/.test(serviceQml),
  'unlock always wakes'
)

assert(
  /if \(!locked && root\.lockRequested\) \{[\s\S]*?root\.forceWake\(\)/.test(serviceQml),
  'losing the session lock always wakes'
)

// The silence is half the bug: nothing in the journal said the blank was skipped.
assert(
  /function runBlank\(\) \{\s*logEvent\("blank-requested"\)/.test(serviceQml),
  'every blank is recorded'
)
JS
