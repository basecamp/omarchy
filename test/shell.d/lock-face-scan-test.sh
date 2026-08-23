#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

// A fingerprint reader idles waiting for a finger, but an armed face scan holds
// the IR camera open and runs inference the whole time. Left armed behind a
// blanked panel it would do that all night with nobody in front of it.
assert(
  /function runBlank\(\) \{[\s\S]*?displayBlanked = true[\s\S]*?faceRetryTimer\.stop\(\)[\s\S]*?facePam\.abort\(\)/.test(serviceQml),
  'blanking the panel stops the face scan loop'
)

assert(
  /function runWake\(\) \{[\s\S]*?displayBlanked = false[\s\S]*?startFace\(\)/.test(serviceQml),
  'waking the panel picks the face scan back up'
)

assert(
  /function startFace\(\) \{[\s\S]*?if \(displayBlanked\) return/.test(serviceQml),
  'a face scan never starts while the panel is blanked'
)

// Face auth is an alternative to the password, not a replacement: the password
// path has to stay reachable even when a camera is enrolled.
assert(
  /if \(root\.lockRequested && !root\.authenticatingPassword\) root\.runBlank\(\)/.test(serviceQml),
  'the blank timer still gates only on password entry'
)

// Enrolled models live under /etc/howdy, which an unprivileged shell cannot
// read, so the PAM service written by setup stands in for the enrollment check.
assert(
  /path: "\/etc\/pam\.d\/omarchy-lock-face"[\s\S]*?onLoaded: root\.faceConfigured = true[\s\S]*?onLoadFailed: root\.faceConfigured = false/.test(serviceQml),
  'the face PAM service file drives whether face auth is offered'
)

assert(
  /config: "omarchy-lock-face"/.test(serviceQml),
  'face auth runs through its own PAM service, separate from the password stack'
)
JS
