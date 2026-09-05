#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const lockView = fs.readFileSync(path.join(root, 'shell/plugins/lock/LockView.qml'), 'utf8')

// Suspending drops focus from the field while the lock is still up. Focus is
// otherwise only taken in Component.onCompleted and when inputEnabled changes,
// and inputEnabled follows lockRequested, which is already true by then, so
// without this handler the machine wakes to a lock screen that ignores the
// keyboard until it is clicked.
assert(
  /onActiveFocusChanged: \{\s*if \(!activeFocus && root\.inputEnabled\) Qt\.callLater\(root\.forcePasswordFocus\)/.test(lockView),
  'the password field reclaims focus when it loses it while the lock is up'
)

// Gating on inputEnabled keeps the unlocked preview surface, which builds the
// same view with inputEnabled false, from fighting the compositor for focus.
assert(
  !/onActiveFocusChanged: \{\s*if \(!activeFocus\) /.test(lockView),
  'focus recovery only runs while the lock is accepting input'
)
JS
