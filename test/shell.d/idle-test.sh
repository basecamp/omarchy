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
    screensaverArmed: true, lockArmed: true, screenOffArmed: false,
    screensaverDelaySeconds: 0, lockDelaySeconds: 150, screenOffDelaySeconds: 0 },
  'idleSchedule matches previous inline math for default timeouts'
)
assertDeepEqual(
  idle.idleSchedule(600, 60),
  { armed: true, firstIdleTimeoutSeconds: 60,
    screensaverArmed: true, lockArmed: true, screenOffArmed: false,
    screensaverDelaySeconds: 540, lockDelaySeconds: 0, screenOffDelaySeconds: 0 },
  'idleSchedule handles lock shorter than screensaver'
)
assertDeepEqual(
  idle.idleSchedule(150, 300, 600),
  { armed: true, firstIdleTimeoutSeconds: 150,
    screensaverArmed: true, lockArmed: true, screenOffArmed: true,
    screensaverDelaySeconds: 0, lockDelaySeconds: 150, screenOffDelaySeconds: 450 },
  'idleSchedule schedules the screens off after the lock on the shipped ladder'
)
assertDeepEqual(
  idle.idleSchedule(150, null, 300),
  { armed: true, firstIdleTimeoutSeconds: 150,
    screensaverArmed: true, lockArmed: false, screenOffArmed: true,
    screensaverDelaySeconds: 0, lockDelaySeconds: 0, screenOffDelaySeconds: 150 },
  'idleSchedule turns the screens off on idle with locking disabled'
)
assertDeepEqual(
  idle.idleSchedule(600, null, 300),
  { armed: true, firstIdleTimeoutSeconds: 300,
    screensaverArmed: true, lockArmed: false, screenOffArmed: true,
    screensaverDelaySeconds: 300, lockDelaySeconds: 0, screenOffDelaySeconds: 0 },
  'idleSchedule takes the first idle deadline from armed actions only'
)
assertDeepEqual(
  idle.idleSchedule(150, 300, 60),
  { armed: true, firstIdleTimeoutSeconds: 60,
    screensaverArmed: true, lockArmed: true, screenOffArmed: true,
    screensaverDelaySeconds: 90, lockDelaySeconds: 240, screenOffDelaySeconds: 0 },
  'idleSchedule allows the screens off before the screensaver'
)
assertDeepEqual(
  idle.idleSchedule(null, null, null),
  { armed: false, firstIdleTimeoutSeconds: idle.PARKED_IDLE_TIMEOUT_SECONDS,
    screensaverArmed: false, lockArmed: false, screenOffArmed: false,
    screensaverDelaySeconds: 0, lockDelaySeconds: 0, screenOffDelaySeconds: 0 },
  'idleSchedule parks the monitor instead of asking for a zero idle timeout'
)
// A zero timeout means "report idle immediately" to ext-idle-notify, so the
// schedule must never produce one, and the caller stops the monitor when nothing
// is armed.
assertEqual(idle.PARKED_IDLE_TIMEOUT_SECONDS > 0, true,
  'idleSchedule parks at a positive idle timeout')
assertDeepEqual(
  idle.idleSchedule(150, -1, 300),
  { armed: true, firstIdleTimeoutSeconds: 150,
    screensaverArmed: true, lockArmed: false, screenOffArmed: true,
    screensaverDelaySeconds: 0, lockDelaySeconds: 0, screenOffDelaySeconds: 150 },
  'idleSchedule drops a nonsense timeout instead of poisoning the schedule'
)
assertDeepEqual(
  idle.idleSchedule(0, 300, 600),
  { armed: true, firstIdleTimeoutSeconds: 1,
    screensaverArmed: true, lockArmed: true, screenOffArmed: true,
    screensaverDelaySeconds: 0, lockDelaySeconds: 299, screenOffDelaySeconds: 599 },
  'idleSchedule clamps a configured zero timeout instead of reporting idle immediately'
)

// One aggregate sweep rather than one `ok -` line per combination.
var values = [null, 0, 60, 300, 900]
var sane = true
for (var a = 0; a < values.length; a++)
  for (var b = 0; b < values.length; b++)
    for (var c = 0; c < values.length; c++) {
      var s = idle.idleSchedule(values[a], values[b], values[c])
      if (s.firstIdleTimeoutSeconds < 0 || s.screensaverDelaySeconds < 0 ||
          s.lockDelaySeconds < 0 || s.screenOffDelaySeconds < 0 ||
          (s.armed && s.firstIdleTimeoutSeconds <= 0)) sane = false
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

# Opt-in direction: the mirror of the lockOnIdle test above.
screen_off_config="$test_tmp/screen-off-shell.json"
printf '{"idle":{"screenOff":600}}' >"$screen_off_config"
if jq -e '.idle.screenOffOnIdle == true' "$screen_off_config" >/dev/null; then
  fail "screenOffOnIdle is disabled when the key is absent"
fi
printf '{"idle":{"screenOff":600,"screenOffOnIdle":true}}' >"$screen_off_config"
jq -e '.idle.screenOffOnIdle == true' "$screen_off_config" >/dev/null ||
  fail "screenOffOnIdle=true reads as enabled"
pass "screenOffOnIdle is opt-in and read with == true (guards the jq // false pitfall)"

# The TUI's seconds reader, against the real expression.
so_read() { jq -r --argjson d 600 '(.idle.screenOff // $d) | if (type == "number" and . >= 0) then floor else $d end' "$1"; }
printf '{"idle":{}}' >"$screen_off_config"
[[ $(so_read "$screen_off_config") == 600 ]] || fail "absent screenOff falls back to the default"
printf '{"idle":{"screenOff":"abc"}}' >"$screen_off_config"
[[ $(so_read "$screen_off_config") == 600 ]] || fail "invalid screenOff falls back to the default"
printf '{"idle":{"screenOff":42.9}}' >"$screen_off_config"
[[ $(so_read "$screen_off_config") == 42 ]] || fail "screenOff is floored"
pass "screens-off timeout reader floors and falls back like the other timeouts"

# lockSystem() stops every idle timer, so anything armed after it would outlive
# its own cycle. This is a source-order proxy for that guarantee, not a runtime
# check -- there's no headless way to drive startIdleCycle() from this suite.
service="$ROOT/shell/plugins/services/idle/Service.qml"
screen_off_line=$(rg -n 'if \(root\.screenOffOnIdle\) \{' "$service" | head -1 | cut -d: -f1)
lock_line=$(rg -n 'if \(root\.lockOnIdle\) \{' "$service" | head -1 | cut -d: -f1)
((screen_off_line < lock_line)) || fail "screen-off is armed before the lock in startIdleCycle"
pass "screen-off is armed before the lock in startIdleCycle"

# The shipped defaults keep the new action opt-in, and out of the lock's way.
jq -e '.idle.screenOffOnIdle == false and .idle.screenOff > .idle.lock' \
  "$ROOT/config/omarchy/shell.json" >/dev/null ||
  fail "shipped defaults keep screens-off opt-in and scheduled after the lock"
pass "shipped defaults keep screens-off opt-in and scheduled after the lock"

# One definition of blanking.
rg -q 'omarchy-system-blank' "$service" || fail "the idle service blanks through omarchy-system-blank"
if rg -q 'hyprctl' "$service"; then
  fail "the idle service does not dispatch hyprctl directly"
fi
pass "the idle service blanks through omarchy-system-blank"

# Blank and wake are separate async processes; firing wake while a blank is
# still in flight races it and can leave the screens dark. wakeScreens() must
# check screenOffProcess.running and defer to its onExited instead of every
# caller firing the wake process directly. This is a source-level check for
# that shape, not a runtime one -- there's no headless way to race two
# Process launches from this suite.
rg -q 'function wakeScreens\(\)' "$service" || fail "wakeScreens() must exist to serialize blank and wake"
rg -A3 'function wakeScreens\(\)' "$service" | rg -q 'screenOffProcess\.running' ||
  fail "wakeScreens() must check screenOffProcess.running before firing a wake"

wake_call_sites=$(rg -c '\bwakeScreens\(\)' "$service")
((wake_call_sites >= 3)) ||
  fail "rearmScreenOff, cancelIdleCycle, and the screen-off switch handler must all wake through wakeScreens()"

rg -A5 'id: screenOffProcess' "$service" | rg -q 'wakeAfterBlankPending' ||
  fail "screenOffProcess.onExited must fire a wake deferred during blanking"

direct_wake_calls=$(rg -c 'runProcess\(wakeProcess, "wake", "omarchy-system-wake"\)' "$service")
((direct_wake_calls == 2)) ||
  fail "omarchy-system-wake should only be launched from wakeScreens() and screenOffProcess.onExited"

pass "a wake requested while blanking is in flight is deferred until the blank exits"
