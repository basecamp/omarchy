#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

// The fingerprint PAM stays armed for the whole lock waiting for a finger, so
// `authenticating` is true from lock until unlock on every machine with a
// reader enrolled. Gating the blank on it leaves the panel lit all night.
assert(
  /if \(root\.lockRequested && !root\.authenticatingPassword\) root\.runBlank\(\)/.test(serviceQml),
  'only a password check in flight stops the blank timer from blanking'
)

assert(
  !/idleBlankTimer[\s\S]*?!root\.authenticating\)/.test(serviceQml),
  'the blank timer never gates on the combined authenticating state'
)

assert(
  /onAuthenticatingPasswordChanged: \{\s*if \(!lockRequested\) return\s*if \(authenticatingPassword\) idleBlankTimer\.stop\(\)\s*else armBlankTimer\(\)/.test(serviceQml),
  'the blank timer is held off by password entry and re-armed when it finishes'
)

assert(
  !/onAuthenticatingChanged:/.test(serviceQml),
  'the combined authenticating state no longer drives the blank timer'
)

assert(
  /function runBlank\(\) \{\s*logEvent\("blanking-display"\)/.test(serviceQml),
  'runBlank logs display blanking event'
)

assert(
  /onScreensChanged\(\) \{[\s\S]*if \(\(root\.locked \|\| root\.lockRequested\) && !root\.authenticatingPassword\) \{[\s\S]*root\.screenChangeBlankCount \+= 1\s*var delay = 5000\s*if \(root\.screenChangeBlankCount === 2\) delay = 15000\s*else if \(root\.screenChangeBlankCount >= 3\) delay = 30000\s*root\.armBlankTimer\(delay\)/.test(serviceQml),
  'screen changes re-arm blanking at 5s, 15s, then cap at 30s only while locked and not authenticating'
)

assert(
  /function runWake\(\) \{\s*screenChangeBlankCount = 0/.test(serviceQml),
  'waking resets the screen change blank count'
)
JS
