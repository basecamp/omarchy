#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')
const viewQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/LockView.qml'), 'utf8')

// The lock knows when it blanked the panel and when a wake brought it back.
assert(/property bool displayBlanked: false/.test(serviceQml), 'the lock tracks whether it blanked the panel')
assert(
  /function runBlank\(\) \{\s*displayBlanked = true/.test(serviceQml),
  'blanking the panel marks the display as blanked'
)
assert(
  /id: wakeProcess[\s\S]*?onExited: root\.displayBlanked = false/.test(serviceQml),
  'a finished wake clears the blanked state'
)
assert(
  /lockRequested = false\s*displayBlanked = false/.test(serviceQml),
  'unlocking clears the blanked state'
)

// Keys hit at a dark panel wake it instead of landing in the password field.
assert(/property bool displayBlanked: false/.test(viewQml), 'the lock view knows when the panel is blanked')
assert(/displayBlanked: root\.displayBlanked/.test(serviceQml), 'the lock view is told when the panel is blanked')
assert(
  /Keys\.onPressed: function\(event\) \{\s*root\.wakeRequested\(\)[\s\S]*?if \(root\.displayBlanked\) \{\s*event\.accepted = true\s*return\s*\}/.test(viewQml),
  'a key pressed at a blanked panel is consumed after requesting the wake'
)

// Resume is detected from the clock jump the frozen shell sees on its first
// tick back, and the panel is woken without waiting for input.
assert(
  /id: resumeWatchTimer[\s\S]*?running: root\.lockRequested[\s\S]*?now - lastTick > interval \+ 2000[\s\S]*?if \(resumed\) \{[\s\S]*?root\.runWake\(\)/.test(serviceQml),
  'the lock wakes the panel on its own after resume'
)
JS
