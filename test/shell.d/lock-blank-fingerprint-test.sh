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
  /function runWake\(force\) \{\s*if \(!force && locked && \(Date\.now\(\) - lastBlankedAt\) < 1500\) return/.test(serviceQml),
  'runWake ignores unforced wake events during the 1.5s post-blanking debounce window'
)

const lockViewQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/LockView.qml'), 'utf8')

assert(
  /signal wakeRequested\(bool force\)/.test(lockViewQml),
  'LockView wakeRequested signal takes a force parameter'
)

assert(
  /onPositionChanged: root\.wakeRequested\(false\)/.test(lockViewQml),
  'LockView passes false for pointer motion wake requests'
)

assert(
  /onClicked: \{ root\.wakeRequested\(true\);/.test(lockViewQml),
  'LockView passes true for deliberate mouse click wake requests'
)
JS
