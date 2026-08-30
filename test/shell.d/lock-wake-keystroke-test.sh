#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')
const lockViewQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/LockView.qml'), 'utf8')

// The blank state has to be tracked where the display is actually turned on
// and off, or the view cannot tell a wake keystroke from a typed character.
assert(
  /function runBlank\(\) \{\s*displayBlanked = true/.test(serviceQml),
  'blanking the display records that it is blanked'
)

assert(
  /function runWake\(\) \{\s*displayBlanked = false/.test(serviceQml),
  'waking the display clears the blanked state'
)

assert(
  /displayBlanked: root\.displayBlanked/.test(serviceQml),
  'the lock surface view is told whether the display is blanked'
)

assert(
  /property bool displayBlanked: false/.test(lockViewQml),
  'the view declares the blanked state it is handed'
)

// wakeRequested() clears the flag, so the handler has to sample it first.
assert(
  /var wokeDisplay = root\.displayBlanked\s*\n\s*root\.wakeRequested\(\)/.test(lockViewQml),
  'the blanked state is sampled before waking clears it'
)

// The keystroke that wakes a blanked display means "wake up", not "here is the
// first character of my password".
assert(
  /if \(wokeDisplay\) event\.accepted = true/.test(lockViewQml),
  'the keystroke that wakes the display is swallowed'
)

// Escape and Ctrl+U still clear the field rather than falling through to the
// swallow.
assert(
  /root\.passwordTextEdited\(""\)\s*\n\s*event\.accepted = true\s*\n\s*return/.test(lockViewQml),
  'clearing the field returns before the wake-keystroke swallow'
)
JS
