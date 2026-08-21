#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const lock = requireFromRoot('shell/plugins/lock/LockModel.js')

assertEqual(lock.secondsFromConfig(30, 5), 30, 'lock blank takes the configured seconds')
assertEqual(lock.secondsFromConfig('30.9', 5), 30, 'lock blank floors configured seconds')
assertEqual(lock.secondsFromConfig(0, 5), 0, 'lock blank allows blanking immediately')
assertEqual(lock.secondsFromConfig(-1, 5), 5, 'lock blank rejects negative seconds')
assertEqual(lock.secondsFromConfig('nope', 5), 5, 'lock blank rejects invalid seconds')
assertEqual(lock.secondsFromConfig(undefined, 5), 5, 'lock blank falls back when unset')

const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

assert(
  /readonly property int defaultBlankSeconds: 5/.test(serviceQml),
  'an unconfigured lock screen still blanks after five seconds'
)

assert(
  /readonly property int blankTimeoutSeconds: LockModel\.secondsFromConfig\(idleConfig\.blank, defaultBlankSeconds\)/.test(serviceQml),
  'the blank timeout comes from idle.blank in shell.json'
)

assert(
  /id: idleBlankTimer\s*interval: root\.blankTimeoutSeconds \* 1000/.test(serviceQml),
  'the blank timer takes its interval from the configured timeout'
)

// Qt restarts a running timer's countdown when the interval changes. Leaving
// `armedAt` behind makes the next trigger read the edit as a suspend gap.
assert(
  /onIntervalChanged: if \(running\) root\.armBlankTimer\(\)/.test(serviceQml),
  'an edited timeout re-arms the blank timer instead of tripping the suspend guard'
)
JS

jq -e '.idle.blank == 5' "$ROOT/config/omarchy/shell.json" >/dev/null
pass "default shell.json ships the lock blank timeout"
