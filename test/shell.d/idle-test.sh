#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const idle = requireFromRoot('shell/plugins/services/idle/IdleModel.js')

assertDeepEqual(idle.stayAwakeState('no', 1000), { enabled: false, until: 0, expired: false }, 'missing state allows idle')
assertDeepEqual(idle.stayAwakeState('yes:', 1000), { enabled: true, until: 0, expired: false }, 'legacy empty state stays awake indefinitely')
assertDeepEqual(idle.stayAwakeState('yes:2000', 1000), { enabled: true, until: 2000, expired: false }, 'future deadline survives reload')
assertDeepEqual(idle.stayAwakeState('yes:1000', 1000), { enabled: false, until: 0, expired: true }, 'deadline expires at boundary')
assertDeepEqual(idle.stayAwakeState('yes:999', 1000), { enabled: false, until: 0, expired: true }, 'past deadline allows idle')
assertDeepEqual(idle.stayAwakeState('yes:invalid', 1000), { enabled: false, until: 0, expired: true }, 'invalid deadline allows idle')

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
JS

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_home="$test_tmp/home"
mkdir -p "$test_home"

HOME="$test_home" "$ROOT/bin/omarchy-toggle-idle" stay-awake >/dev/null
[[ -f $test_home/.local/state/omarchy/indicators/stay-awake ]] || fail "Stay Awake toggle persists enabled state"

printf '9999999999999' > "$test_home/.local/state/omarchy/indicators/stay-awake"
HOME="$test_home" "$ROOT/bin/omarchy-toggle-idle" stay-awake >/dev/null
[[ ! -s $test_home/.local/state/omarchy/indicators/stay-awake ]] || fail "Indefinite Stay Awake clears deadline"

HOME="$test_home" "$ROOT/bin/omarchy-toggle-idle" allow-idle >/dev/null
[[ ! -f $test_home/.local/state/omarchy/indicators/stay-awake ]] || fail "Stay Awake toggle persists disabled state"

if rg -q 'omarchy-shell' "$ROOT/bin/omarchy-toggle-idle"; then
  fail "Stay Awake toggle avoids reentrant shell IPC"
fi

pass "Stay Awake toggle persists state without reentrant shell IPC"
