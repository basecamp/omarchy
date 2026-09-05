#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const idle = requireFromRoot('shell/plugins/services/idle/IdleModel.js')

assertEqual(idle.secondsFromConfig('42.9', 10), 42, 'idle floors configured seconds')
assertEqual(idle.secondsFromConfig('-1', 10), 10, 'idle rejects negative seconds')
assertEqual(idle.secondsFromConfig('nope', 10), 10, 'idle rejects invalid seconds')

assertDeepEqual(idle.eventParts({ data: 'a,b,c' }, 2), ['a', 'b', 'c'], 'idle parses raw event data')
assertDeepEqual(
  idle.eventParts({ parse: function(count) { return ['parsed', count] } }, 4),
  ['parsed', 4],
  'idle prefers event parser when available'
)

assertDeepEqual(
  idle.screensaverWindowsAfter({ a: true }, 'b', true),
  { windows: { a: true, b: true }, count: 2 },
  'idle adds visible screensaver windows'
)
assertDeepEqual(
  idle.screensaverWindowsAfter({ a: true, b: true }, 'a', false),
  { windows: { b: true }, count: 1 },
  'idle removes closed screensaver windows'
)
assertDeepEqual(
  idle.screensaverWindowsAfter({ a: true }, '', false),
  { windows: { a: true }, count: 1 },
  'idle leaves screensaver windows unchanged without an address'
)

const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/services/idle/Service.qml'), 'utf8')

// The lock plugin runs in this process, so its state is readable without the
// shell-out, which reports nothing at all when the IPC call fails.
assert(
  /readonly property var lockService: shell && shell\.serviceFor \? shell\.serviceFor\("omarchy\.lock"\) : null/.test(serviceQml),
  'the idle service reads lock state from the lock service in-process'
)

// omarchy-system-lock takes about a second to reach the lock service, and the
// lock is not visible anywhere until it gets there.
assert(
  /readonly property bool lockInFlight: lockCommandPending \|\| !!\(lockService && lockService\.locked\)/.test(serviceQml),
  'a lock counts as in flight from the moment its command is spawned'
)

assert(
  /if \(runProcess\(lockProcess, "lock", "omarchy-system-lock"\)\) \{\s*\n\s*root\.lockCommandPending = true\s*\n\s*lockCommandTimer\.restart\(\)/.test(serviceQml),
  'spawning the lock command marks it pending'
)

// A lock command that never returns would otherwise park idle handling for the
// rest of the session.
assert(
  /id: lockProcess\s*\n\s*onExited: function\(exitCode, exitStatus\) \{\s*\n\s*root\.lockCommandPending = false/.test(serviceQml),
  'the lock command stops being pending when it exits'
)

assert(
  /id: lockCommandTimer\s*\n\s*interval: 15000[\s\S]{0,200}?root\.lockCommandPending = false/.test(serviceQml),
  'a lock command that never exits stops being pending on its own'
)

// lockSystem() clears idledThisCycle, so the next idle re-assertion would
// otherwise start a fresh cycle on top of the lock it just asked for.
assert(
  /if \(root\.lockInFlight\) \{\s*\n\s*logEvent\("idle-cycle-skip", "lock-in-flight"\)\s*\n\s*return\s*\n\s*\}\s*\n\s*logEvent\("idle-cycle-start"/.test(serviceQml),
  'no idle cycle begins while a lock is in flight'
)

// screensaver <= lock makes screensaverDelaySeconds 0, so a cycle that slips
// through launches a screensaver into the pending lock immediately.
assert(
  /function launchScreensaver\(\) \{\s*\n\s*if \(root\.lockInFlight\) \{\s*\n\s*logEvent\("screensaver-skip", "lock-in-flight"\)\s*\n\s*return/.test(serviceQml),
  'no screensaver launches while a lock is in flight'
)
JS

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_home="$test_tmp/home"
mkdir -p "$test_home"

HOME="$test_home" "$ROOT/bin/omarchy-toggle-idle" stay-awake >/dev/null
[[ -f $test_home/.local/state/omarchy/indicators/stay-awake ]] || fail "Stay Awake toggle persists enabled state"

HOME="$test_home" "$ROOT/bin/omarchy-toggle-idle" allow-idle >/dev/null
[[ ! -f $test_home/.local/state/omarchy/indicators/stay-awake ]] || fail "Stay Awake toggle persists disabled state"

if rg -q 'omarchy-shell' "$ROOT/bin/omarchy-toggle-idle"; then
  fail "Stay Awake toggle avoids reentrant shell IPC"
fi

pass "Stay Awake toggle persists state without reentrant shell IPC"
