#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')

const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

// The person who pressed Super+Ctrl+L is still at the keyboard. Scanning the
// moment the lock lands would unlock straight back into their session, so the
// secure transition arms fingerprint only and never a face scan.
const secureHandler = serviceQml.match(/onSecureStateChanged: \{[\s\S]*?\n    \}/)
assert(secureHandler, 'the session lock has a secure-state handler')
assert(
  /root\.startFingerprint\(\)/.test(secureHandler[0]),
  'the secure transition still arms the fingerprint reader'
)
assert(
  !/startFace/.test(secureHandler[0]),
  'the secure transition never starts a face scan'
)

// Face scans are driven by someone arriving at the machine: the first key or
// pointer event after a quiet gap. Both the gap and the lock keystroke's own
// timestamp are what keep a lock-then-type sequence from scanning.
assert(
  /readonly property int faceIdleGap: \d+/.test(serviceQml),
  'the arrival gap is a named constant'
)
assert(
  /function noteInput\(\) \{[\s\S]*?if \(idle > faceIdleGap\) startFace\(false\)/.test(serviceQml),
  'the first input after the gap starts one silent scan'
)
assert(
  /function beginLock\(\) \{[\s\S]*?lastInputAt = Date\.now\(\)[\s\S]*?queueSessionLock\(\)/.test(serviceQml),
  'locking counts as input so the lock keystroke does not open the gap'
)
assert(
  /onWakeRequested: root\.noteInput\(\)/.test(serviceQml),
  'the lock surface routes its input events through noteInput'
)

// A single bounded scan per trigger: no retry timer for face, unlike the
// fingerprint reader which is cheap to keep armed.
assert(
  !/faceRetryTimer/.test(serviceQml),
  'face auth never retries on its own'
)
assert(
  /if \(facePam\.active \|\| faceAuthenticating\) \{[\s\S]*?if \(explicit === true\) faceExplicit = true[\s\S]*?return/.test(serviceQml),
  'an Enter during a running scan promotes it to an explicit one instead of starting another'
)
JS
