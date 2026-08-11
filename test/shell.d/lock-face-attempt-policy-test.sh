#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

assert(
  /readonly property int faceAttemptLimit: 3/.test(serviceQml) &&
    /readonly property int faceRetryDelay: 250/.test(serviceQml),
  'face authentication has bounded attempt and retry policy'
)

assert(
  /function activateFaceAuthentication\(\) \{[\s\S]*faceAttemptCount > 0[\s\S]*startFaceAttempt\(\)[\s\S]*return faceAttemptCount > 0/.test(serviceQml),
  'a face activation request does not interrupt an active or pending attempt'
)

assert(
  /function startFaceAttempt\(\) \{[\s\S]*!lockRequested \|\| !sessionLock\.secure \|\| !faceConfigured[\s\S]*faceAttemptCount \+= 1[\s\S]*facePam\.start\(\)/.test(serviceQml),
  'each face PAM start rechecks lock safety and consumes attempt budget'
)

assert(
  /function finishFaceAttempt\(succeeded\)[\s\S]*if \(succeeded\)[\s\S]*finishUnlock\(\)[\s\S]*faceAttemptCount < faceAttemptLimit[\s\S]*faceRetryTimer\.restart\(\)[\s\S]*faceAttemptCount = 0/.test(serviceQml),
  'face completion unlocks on success, retries within budget, then disarms'
)

assert(
  /function resetFaceAuthentication\(\)[\s\S]*faceRetryTimer\.stop\(\)[\s\S]*faceAttemptCount = 0[\s\S]*facePam\.abort\(\)/.test(serviceQml),
  'intentional cleanup stops retries and aborts active face PAM'
)

assert(
  /onSecureStateChanged:[\s\S]*if \(secure\)[\s\S]*else \{\s*root\.resetFaceAuthentication\(\)/.test(serviceQml),
  'losing secure lock state immediately cancels face authentication'
)

assert(
  /id: faceRetryTimer\s*interval: root\.faceRetryDelay\s*repeat: false\s*onTriggered: root\.startFaceAttempt\(\)/.test(serviceQml),
  'face retry timer is one-shot and starts the next attempt'
)
JS
