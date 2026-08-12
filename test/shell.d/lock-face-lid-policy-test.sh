#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

assert(
  /id: lidCheckProc\s*command: \["omarchy-hw-laptop-closed"\]/.test(serviceQml),
  'lid state is observed through the existing hardware helper'
)

assert(
  /readonly property int lidPollInterval: 1000/.test(serviceQml) &&
    /id: lidPollTimer\s*interval: root\.lidPollInterval\s*repeat: true\s*running: root\.lockRequested && root\.faceConfigured && root\.faceAttemptCount === 0\s*triggeredOnStart: true/.test(serviceQml),
  'lid state is polled immediately and then every second while observation is needed'
)

assert(
  /onTriggered: \{\s*if \(!lidCheckProc\.running\) lidCheckProc\.running = true/.test(serviceQml),
  'lid polling never overlaps helper processes'
)

assert(
  /if \(!root\.lockRequested \|\| !root\.faceConfigured\) return/.test(serviceQml),
  'a stale lid result after unlock or configuration removal is ignored'
)

assert(
  /if \(exitCode === 0\) \{\s*root\.lidClosedDuringLock = true\s*\} else if \(root\.lidClosedDuringLock && sessionLock\.secure\)/.test(serviceQml),
  'an open result activates only after this lock observed a closed lid and became secure'
)

assert(
  /else if \(root\.lidClosedDuringLock && sessionLock\.secure\) \{[\s\S]*root\.lidClosedDuringLock = false\s*root\.activateFaceAuthentication\(\)/.test(serviceQml),
  'a secure closed-to-open transition consumes its latch before activating face PAM'
)

assert(
  /function resetFaceAuthentication\(\)[\s\S]*lidClosedDuringLock = false/.test(serviceQml),
  'unlock cleanup clears the per-lock closed latch'
)

assert(
  /onFaceConfiguredChanged:[\s\S]*if \(!faceConfigured\)[\s\S]*resetFaceAuthentication\(\)[\s\S]*else if \(lockRequested\)[\s\S]*if \(sessionLock\.secure\) faceActivityEligibleAt = Date\.now\(\)/.test(serviceQml),
  'live face PAM configuration updates activity eligibility while timer bindings handle polling'
)
JS
