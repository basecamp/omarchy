#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')
const lockViewQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/LockView.qml'), 'utf8')
const sleepLock = fs.readFileSync(path.join(root, 'bin/omarchy-system-sleep-lock'), 'utf8')

// The blank state has to be tracked where the display is actually turned on
// and off, or the view cannot tell a wake keystroke from a typed character.
assert(
  /property bool displayBlanked: false/.test(serviceQml),
  'the lock tracks whether it blanked the display'
)

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
  /var waking = root\.displayBlanked \|\| root\.swallowingWakeKey\s*\n\s*root\.wakeRequested\(\)/.test(lockViewQml),
  'the blanked state is sampled before waking clears it'
)

// The keystroke that wakes a blanked display means "wake up", not "here is the
// first character of my password".
assert(
  /if \(waking\) \{\s*root\.swallowingWakeKey = true\s*event\.accepted = true/.test(lockViewQml),
  'the keystroke that wakes the display is swallowed'
)

// Holding the wake key would otherwise fill the field with auto-repeats once
// runWake() has already cleared displayBlanked.
assert(
  /Keys\.onReleased: function\(event\) \{\s*if \(!root\.swallowingWakeKey\) return\s*root\.swallowingWakeKey = false/.test(lockViewQml),
  'auto-repeats of the wake key are swallowed until that key is released'
)

// Escape and Ctrl+U still clear the field rather than falling through to the
// swallow.
assert(
  /root\.passwordTextEdited\(""\)\s*\n\s*event\.accepted = true\s*\n\s*return/.test(lockViewQml),
  'clearing the field returns before the wake-keystroke swallow'
)

// Lid-close suspend often wins the race against the lock's five-second blank
// timer, so the sleep path has to mark the panel blanked before the machine
// goes down. Frozen QML state then still says "blanked" on the first key
// after resume.
assert(
  /function blank\(\): string \{\s*if \(!root\.lockRequested\) return "not-locked"\s*root\.runBlank\(\)\s*return "ok"/.test(serviceQml),
  'the lock can be told to blank over IPC'
)

assert(
  /secure\)[\s\S]*?lock blank/.test(sleepLock),
  'sleep lock blanks the display once the session is secure'
)
JS
