#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
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

assertEqual(idle.wakeAfterIdle(true, false), true, 'idle wakes the display after a cycle it ran')
assertEqual(idle.wakeAfterIdle(true, true), false, 'idle leaves a locked session\'s display to the lock screen')
assertEqual(idle.wakeAfterIdle(false, false), false, 'idle does not wake a display it never put to sleep')
assertEqual(idle.wakeAfterIdle(false, true), false, 'idle does not wake a locked display it never put to sleep')

// Hyprland sends ext-idle "resumed" the moment an idle inhibitor appears, so a
// browser starting media on a background workspace reads as activity at a
// blanked lock screen. Waking there lights the display with nothing to blank
// it again. The compositor fixture proves the behaviour; these keep the wiring
// honest on machines where that fixture has to skip.
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/services/idle/Service.qml'), 'utf8')
assert(
  /wakeAfterIdle\(root\.idledThisCycle, root\.sessionLocked\)[^\n]*runProcess\(wakeProcess/.test(serviceQml),
  'the idle service consults the lock before waking the display'
)
assert(
  !/if \(root\.idledThisCycle\) runProcess\(wakeProcess/.test(serviceQml),
  'no unconditional display wake remains in the idle service'
)
assert(
  /sessionLocked:[^\n]*lockService[^\n]*\.locked/.test(serviceQml),
  'the idle service reads the lock state from the in-process lock service'
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
