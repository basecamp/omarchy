#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(`${root}/shell/plugins/lock/Service.qml`, 'utf8')
const viewQml = fs.readFileSync(`${root}/shell/plugins/lock/LockView.qml`, 'utf8')

assert(
  /function beginPasswordFocusRecovery\(completeBudget\)[\s\S]*focusRecoveryTimer\.completeBudget = Boolean\(completeBudget\)[\s\S]*focusRecoveryTimer\.remaining = focusRecoveryTimer\.attemptBudget[\s\S]*requestPasswordFocus\(\)[\s\S]*focusRecoveryTimer\.restart\(\)/.test(serviceQml),
  'focus recovery starts with a complete retry budget'
)

assert(
  /function onScreensChanged\(\) \{[\s\S]*root\.requestSessionLock\(\)[\s\S]*root\.beginPasswordFocusRecovery\(\)/.test(serviceQml),
  'output recreation restarts password focus recovery'
)

assert(
  /onAuthenticatingPasswordChanged: \{[\s\S]*if \(authenticatingPassword\) \{[\s\S]*focusRecoveryTimer\.stop\(\)[\s\S]*else \{[\s\S]*beginPasswordFocusRecovery\(\)/.test(serviceQml),
  'password focus recovery restarts after PAM releases the disabled field'
)

assert(
  /function requestPasswordFocus\(\) \{\s*if \(!root\.lockRequested \|\| root\.authenticatingPassword\) return/.test(serviceQml),
  'focus requests never target the disabled field during authentication'
)

assert(
  /if \(!root\.lockRequested \|\| root\.authenticatingPassword \|\| remaining <= 0\)[\s\S]*if \(!completeBudget && root\.passwordFocusAcquired && remaining <= attemptBudget - 4\) stop\(\)/.test(serviceQml),
  'focus recovery survives sequential multi-monitor recreation'
)

assert(
  /remaining -= 1[\s\S]*if \(remaining <= 0\) \{[\s\S]*completeBudget = false[\s\S]*stop\(\)/.test(serviceQml),
  'a complete resume recovery budget stops cleanly when exhausted'
)

assert(
  /function resumeFromSleep\(\): string \{[\s\S]*if \(!root\.lockRequested\) return "idle"[\s\S]*root\.beginPasswordFocusRecovery\(true\)/.test(serviceQml),
  'an explicit post-resume event starts the complete focus retry budget'
)

assert(
  /FocusScope \{[\s\S]*focus: true/.test(viewQml),
  'the lock view owns a keyboard focus scope'
)

assert(
  /onFocusGenerationChanged: \{\s*if \(inputEnabled && !authenticatingPassword\) Qt\.callLater\(forcePasswordFocus\)/.test(viewQml),
  'service focus requests reach the password input'
)

assert(
  /onAuthenticatingPasswordChanged: \{\s*if \(inputEnabled && !authenticatingPassword\) Qt\.callLater\(forcePasswordFocus\)/.test(viewQml),
  'the re-enabled password input requests focus after a failed attempt'
)

assert(
  /readonly property bool passwordFocused: passwordInput\.activeFocus[\s\S]*if \(passwordFocused\) root\.passwordFocusAcquired\(\)/.test(viewQml),
  'the password input acknowledges acquired focus'
)
JS
