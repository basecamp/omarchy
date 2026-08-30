#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const idle = requireFromRoot('shell/plugins/services/idle/IdleModel.js')

assertEqual(idle.secondsFromConfig('42.9', 10), 42, 'idle floors configured seconds')
assertEqual(idle.secondsFromConfig(0, 10), 0, 'idle keeps a zero timeout immediate')
assertEqual(idle.secondsFromConfig(undefined, 10), 10, 'idle defaults an unset timing')
assertEqual(idle.secondsFromConfig('nope', 10), 10, 'idle rejects invalid seconds')
assertEqual(idle.secondsFromConfig('', 10), 10, 'idle treats a blank timing as unset')
assertEqual(idle.secondsFromConfig(true, 10), 10, 'idle treats true as unset')

assertEqual(idle.secondsFromConfig(null, 10), idle.DISABLED_SECONDS, 'idle disables on null')
assertEqual(idle.secondsFromConfig(false, 10), idle.DISABLED_SECONDS, 'idle disables on false')
assertEqual(idle.secondsFromConfig('off', 10), idle.DISABLED_SECONDS, 'idle disables on off')
assertEqual(idle.secondsFromConfig(' Never ', 10), idle.DISABLED_SECONDS, 'idle disables on never')
assertEqual(idle.secondsFromConfig('-1', 10), idle.DISABLED_SECONDS, 'idle disables on negative seconds')

assertEqual(
  idle.secondsFromConfig(999999999, 10),
  idle.MAX_SECONDS,
  'idle clamps timings to the 32-bit timer ceiling'
)

assert(idle.isDisabled(idle.DISABLED_SECONDS), 'idle recognises the disabled sentinel')
assert(!idle.isDisabled(0), 'idle does not treat zero as disabled')

assertEqual(idle.firstIdleTimeout(150, 300), 150, 'idle arms at the earliest timing')
assertEqual(idle.firstIdleTimeout(150, idle.DISABLED_SECONDS), 150, 'idle ignores a disabled lock')
assertEqual(idle.firstIdleTimeout(idle.DISABLED_SECONDS, 300), 300, 'idle ignores a disabled screensaver')
assertEqual(
  idle.firstIdleTimeout(idle.DISABLED_SECONDS, idle.DISABLED_SECONDS),
  0,
  'idle has nothing to arm when both timings are disabled'
)

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
