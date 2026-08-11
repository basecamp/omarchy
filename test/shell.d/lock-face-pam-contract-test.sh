#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')
const lockViewQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/LockView.qml'), 'utf8')
const manifest = require(path.join(root, 'shell/plugins/lock/manifest.json'))

assert(
  /property bool faceAuthenticating: false/.test(serviceQml) &&
    /property bool faceConfigured: false/.test(serviceQml),
  'face PAM configuration and authentication have independent state'
)

assert(
  /readonly property bool authenticating: authenticatingPassword \|\| fingerprintAuthenticating \|\| faceAuthenticating/.test(serviceQml),
  'aggregate authentication state includes face PAM activity'
)

const facePamMatch = serviceQml.match(/PamContext \{\s*id: facePam([\s\S]*?)\n  \}/)
assert(facePamMatch, 'the lock service has an independent face PAM context')
const facePam = facePamMatch ? facePamMatch[1] : ''

assert(
  /config: "omarchy-lock-face"/.test(facePam) && /user: root\.userName/.test(facePam),
  'face PAM uses the backend-neutral service for the current user'
)

assert(
  /onCompleted: function\(result\)[\s\S]*root\.finishFaceAttempt\(result === PamResult\.Success\)/.test(facePam) &&
    /function finishFaceAttempt\(succeeded\)[\s\S]*if \(succeeded\)[\s\S]*finishUnlock\(\)/.test(serviceQml),
  'face PAM success uses the shared unlock path'
)

for (const passwordState of [
  'enteredPassword',
  'pendingPassword',
  'failureMessage',
  'failedAttempts',
  'handlePasswordFailure',
  'passwordPam'
]) {
  assert(
    !facePam.includes(passwordState),
    `face PAM completion does not alter password state through ${passwordState}`
  )
}

assert(
  /function resetFaceAuthentication\(\)[\s\S]*faceAuthenticating = false[\s\S]*if \(facePam\.active\) facePam\.abort\(\)/.test(serviceQml) &&
    /function resetAuthenticationState\(\)[\s\S]*resetFaceAuthentication\(\)/.test(serviceQml),
  'lock cleanup clears and aborts face authentication'
)

assert(
  /FileView \{\s*path: "\/etc\/pam\.d\/omarchy-lock-face"[\s\S]*watchChanges: true[\s\S]*onLoaded: root\.faceConfigured = true[\s\S]*onLoadFailed: root\.faceConfigured = false[\s\S]*onFileChanged: reload\(\)/.test(serviceQml),
  'face availability watches the backend-owned PAM service file'
)

assert(
  /onFaceConfiguredChanged:[\s\S]*if \(!faceConfigured\) resetFaceAuthentication\(\)/.test(serviceQml),
  'removing face configuration aborts its active PAM transaction'
)

assert(
  (serviceQml.match(/faceConfigured: root\.faceConfigured/g) || []).length === 2,
  'face configuration reaches both lock and preview views'
)

assert(
  /face: root\.faceConfigured/.test(serviceQml),
  'lock status exposes face configuration'
)

assert(
  /enabled: root\.inputEnabled && !root\.authenticatingPassword/.test(lockViewQml) &&
    /readOnly: root\.authenticatingPassword/.test(lockViewQml),
  'password input remains controlled only by password authentication'
)

assert(
  manifest.version === '1.1.0' && /password, fingerprint, and face PAM flows/.test(manifest.description),
  'lock manifest describes the expanded PAM contract'
)
JS
