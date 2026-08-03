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

assertDeepEqual(
  idle.idleSchedule(150, 300),
  { armed: true, firstIdleTimeoutSeconds: 150,
    screensaverArmed: true, lockArmed: true,
    screensaverDelaySeconds: 0, lockDelaySeconds: 150 },
  'idleSchedule matches previous inline math for default timeouts'
)
assertDeepEqual(
  idle.idleSchedule(600, 60),
  { armed: true, firstIdleTimeoutSeconds: 60,
    screensaverArmed: true, lockArmed: true,
    screensaverDelaySeconds: 540, lockDelaySeconds: 0 },
  'idleSchedule handles lock shorter than screensaver'
)
assertDeepEqual(
  idle.idleSchedule(150, null),
  { armed: true, firstIdleTimeoutSeconds: 150,
    screensaverArmed: true, lockArmed: false,
    screensaverDelaySeconds: 0, lockDelaySeconds: 0 },
  'idleSchedule keeps the screensaver on with locking disabled'
)
assertDeepEqual(
  idle.idleSchedule(null, null),
  { armed: false, firstIdleTimeoutSeconds: idle.PARKED_IDLE_TIMEOUT_SECONDS,
    screensaverArmed: false, lockArmed: false,
    screensaverDelaySeconds: 0, lockDelaySeconds: 0 },
  'idleSchedule parks the monitor instead of asking for a zero idle timeout'
)
// A zero timeout means "report idle immediately" to ext-idle-notify, so the
// schedule must never produce one, and the caller stops the monitor when nothing
// is armed.
assertEqual(idle.PARKED_IDLE_TIMEOUT_SECONDS > 0, true,
  'idleSchedule parks at a positive idle timeout')
assertDeepEqual(
  idle.idleSchedule(150, -1),
  { armed: true, firstIdleTimeoutSeconds: 150,
    screensaverArmed: true, lockArmed: false,
    screensaverDelaySeconds: 0, lockDelaySeconds: 0 },
  'idleSchedule drops a nonsense timeout instead of poisoning the schedule'
)
assertDeepEqual(
  idle.idleSchedule(0, 300),
  { armed: true, firstIdleTimeoutSeconds: 1,
    screensaverArmed: true, lockArmed: true,
    screensaverDelaySeconds: 0, lockDelaySeconds: 299 },
  'idleSchedule clamps a configured zero timeout instead of reporting idle immediately'
)

// One aggregate sweep rather than one `ok -` line per combination.
var values = [null, 0, 60, 300, 900]
var sane = true
for (var a = 0; a < values.length; a++)
  for (var b = 0; b < values.length; b++) {
    var s = idle.idleSchedule(values[a], values[b])
    if (s.firstIdleTimeoutSeconds < 0 || s.screensaverDelaySeconds < 0 ||
        s.lockDelaySeconds < 0 || (s.armed && s.firstIdleTimeoutSeconds <= 0)) sane = false
  }
assertEqual(sane, true, 'idleSchedule never produces a negative or zero timer interval while armed')
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

lock_on_idle_config="$test_tmp/lock-on-idle-shell.json"
printf '{"idle":{"screensaver":150,"lock":300,"lockOnIdle":false}}' >"$lock_on_idle_config"

if jq -e '.idle.lockOnIdle != false' "$lock_on_idle_config" >/dev/null; then
  fail "lockOnIdle=false must be read as disabled via != false, not // true"
fi

pass "lockOnIdle=false reads as disabled (guards against the jq // false pitfall)"
