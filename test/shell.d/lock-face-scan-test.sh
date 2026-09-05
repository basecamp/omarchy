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
  /function startFace\(\) \{[\s\S]*?if \(displayBlanked \|\| !sessionForeground\) return/.test(serviceQml),
  'a face scan never starts while the panel is blanked'
)

// Face auth is an alternative to the password, not a replacement: the password
// path has to stay reachable even when a camera is enrolled.
assert(
  /onTriggered: \{[\s\S]*?if \(!root\.lockRequested \|\| root\.authenticatingPassword\) return/.test(serviceQml),
  'password entry still holds the panel up on its own'
)

// A scan already in flight owns a bounded transaction the backend finishes by
// itself. Blanking through it throws away a result that may already be a match,
// which is what a backend slower than the 5s blank timer runs into.
assert(
  /if \(root\.faceAuthenticating\) \{[\s\S]*?root\.blankPending = true[\s\S]*?faceRetryTimer\.stop\(\)[\s\S]*?blankDeferTimer\.restart\(\)[\s\S]*?return/.test(serviceQml),
  'the blank timer defers to a face scan in flight instead of aborting it'
)

// Deferring is not waiting forever: the loop stops immediately, only the one
// attempt underway is waited on, and a backend that never reports back hits a
// ceiling rather than holding the camera open all night.
assert(
  /function handleFaceFinished\([\s\S]*?if \(blankPending\) \{\s*runBlank\(\)/.test(serviceQml),
  'a finished face scan runs the blank it deferred'
)

assert(
  /id: blankDeferTimer[\s\S]*?onTriggered: \{\s*if \(root\.blankPending\) root\.runBlank\(\)/.test(serviceQml),
  'a face scan that never reports back stops holding the panel up'
)

// Switching VT hides the lock without blanking the panel. A fingerprint lane can
// stay armed through that, because a finger is placed deliberately; a passive
// face scan cannot, or it unlocks a session nobody is looking at while the
// display shows another console.
assert(
  /function startFace\(\) \{[\s\S]*?if \(displayBlanked \|\| !sessionForeground\) return/.test(serviceQml),
  'a face scan never starts while another VT is in the foreground'
)

assert(
  /onSessionForegroundChanged: \{[\s\S]*?\} else \{[\s\S]*?faceRetryTimer\.stop\(\)[\s\S]*?facePam\.abort\(\)/.test(serviceQml),
  'switching away from this session stops a face scan already in flight'
)

assert(
  /onSessionForegroundChanged: \{\s*if \(sessionForeground\) \{\s*startFace\(\)/.test(serviceQml),
  'switching back to this session picks the face scan up again'
)

// sysfs delivers no inotify events, so the active VT is polled rather than
// watched, and only while a lock that could be scanning is up.
assert(
  /id: activeVtView[\s\S]*?path: "\/sys\/class\/tty\/tty0\/active"[\s\S]*?onLoaded: root\.sessionForeground = text\(\)\.trim\(\) === root\.sessionVt/.test(serviceQml),
  'the console\'s active VT decides whether this session is in the foreground'
)

assert(
  /id: activeVtTimer[\s\S]*?running: root\.lockRequested && root\.faceConfigured/.test(serviceQml),
  'the active-VT poll only runs while a lock with face auth is up'
)

// An unreadable /sys path must not take face auth away entirely.
assert(
  /id: activeVtView[\s\S]*?onLoadFailed: root\.sessionForeground = true/.test(serviceQml),
  'a VT that cannot be read leaves face auth working'
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

// Running on its own service is what makes the terminator necessary. A face
// module that cannot reach its backend returns PAM_IGNORE instead of failing,
// which is safe on sudo or a greeter because the password sits behind it in the
// same stack. Here nothing sits behind it, and a stack that reaches its end with
// no verdict authenticates. Measured against a stopped backend: the stack let
// pamtester in, in 0.1s, until pam_deny closed it, and a non-matching face got
// in the same way. The module has to be sufficient rather than required, or
// pam_deny would overrule a genuine match and refuse everyone.
const setupFace = fs.readFileSync(path.join(root, 'bin/omarchy-setup-security-face'), 'utf8')

assert(
  /\/etc\/pam\.d\/omarchy-lock-face[\s\S]*?auth\s+sufficient\s+pam_howdy\.so[\s\S]*?auth\s+required\s+pam_deny\.so[\s\S]*?EOF/.test(setupFace),
  'the face PAM stack ends in pam_deny, with the module sufficient so a match still passes'
)
JS
