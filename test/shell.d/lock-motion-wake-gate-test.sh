#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')
const lockViewQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/LockView.qml'), 'utf8')

// Rebuilding the lock surface for a returning output can synthesize pointer
// motion. Motion therefore travels on its own signal, distinct from the
// deliberate-input wake, so the service can gate it.
assert(
  /signal motionWakeRequested\(\)/.test(lockViewQml),
  'LockView declares a dedicated motion wake signal'
)

assert(
  /onPositionChanged: root\.motionWakeRequested\(\)/.test(lockViewQml),
  'pointer motion emits the motion signal, not the deliberate wake'
)

assert(
  /onClicked: \{ root\.wakeRequested\(\); root\.forcePasswordFocus\(\) \}/.test(lockViewQml),
  'clicks stay on the deliberate wake and still focus the password field'
)

// The service must stamp screen changes and gate motion on that stamp: motion
// within the window re-arms the blank (a returning monitor goes dark again)
// instead of waking the whole desk.
assert(
  /property double lastScreensChangeAt: 0/.test(serviceQml),
  'the service tracks when the screens last changed'
)

assert(
  /function onScreensChanged\(\) \{\s*root\.lastScreensChangeAt = Date\.now\(\)/.test(serviceQml),
  'every screens change refreshes the stamp before anything else reacts'
)

assert(
  /onMotionWakeRequested: \{\s*if \(Date\.now\(\) - root\.lastScreensChangeAt < 10000\) \{\s*if \(root\.lockRequested\) root\.armBlankTimer\(\)\s*\} else \{\s*root\.runWake\(\)\s*\}/.test(serviceQml),
  'motion inside the window re-arms the blank; motion outside it wakes'
)

// The deliberate wake path is untouched: wakeRequested still wakes directly.
assert(
  /onWakeRequested: root\.runWake\(\)/.test(serviceQml),
  'deliberate input still wakes immediately'
)
JS
