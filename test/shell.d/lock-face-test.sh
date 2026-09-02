#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceSource = fs.readFileSync(root + '/shell/plugins/lock/Service.qml', 'utf8')
const manifestSource = fs.readFileSync(root + '/shell/plugins/lock/manifest.json', 'utf8')

assert(/config:\s*"omarchy-lock-howdy"/.test(serviceSource), 'lock service declares omarchy-lock-howdy PAM context')
assert(/function startFace\(\)/.test(serviceSource), 'lock service implements startFace lifecycle')
assert(/faceAttemptTimer/.test(serviceSource), 'lock service includes face attempt timeout')
assert(/resumeDetectionTimer/.test(serviceSource), 'lock service detects system resume to re-trigger face unlock')
assert(/facePamConfigured/.test(serviceSource), 'lock service tracks /etc/pam.d/omarchy-lock-howdy availability')
assert(/faceAuthenticating/.test(serviceSource), 'lock service reports face authenticating state')
assert(/separate password, fingerprint, and face PAM flows/.test(manifestSource), 'lock manifest documents face PAM flow')
JS

pass "lock service integrates face authentication PAM flow"
