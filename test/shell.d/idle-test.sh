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

# Print one top-level QML block (a function, handler, or object) by its opening
# line, up to its own closing brace. Assertions below scope themselves to a
# block instead of a fixed -A window, which silently stops covering the thing
# it names as soon as the block grows a line.
qml_block() { awk -v want="$1" 'index($0, want) { inside = 1 } inside { print } inside && /^  \}$/ { exit }' "$service"; }
screen_off_line=$(rg -n 'if \(root\.screenOffOnIdle && !root\.screenOffSubsumedByLock\) \{' "$service" | head -1 | cut -d: -f1)
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

# Blanking and waking are two async processes over one resource: whichever
# exits last decides what the displays do, so launching either while the other
# runs races it, and refusing to launch drops the request. Both directions are
# reachable with the one-second rearm floor. Neither process may be launched
# outside the serializer, the serializer must wait on BOTH of them, and the
# wanted state may only clear once its process actually started -- with both
# exits flushing, so nothing is silently lost. Source-level checks for that
# shape; there is no headless way to race two Process launches from this suite.
for helper in turnOffScreens wakeScreens flushDisplayState; do
  rg -q "function $helper\(" "$service" || fail "$helper() must exist"
done

qml_block 'function flushDisplayState()' | rg -q 'if \(screenOffProcess\.running \|\| wakeProcess\.running\) return' ||
  fail "flushDisplayState() must wait for both the blank and the wake process, not just one"
qml_block 'function flushDisplayState()' | rg -q 'if \(started\) root\.pendingDisplayState = ""' ||
  fail "flushDisplayState() must only clear the wanted state once its process actually launched"

for launch in 'runProcess\(screenOffProcess, "screen-off", "omarchy-system-blank"\)' 'runProcess\(wakeProcess, "wake", "omarchy-system-wake"\)'; do
  launches=$(rg -c "$launch" "$service")
  ((launches == 1)) || fail "each display process must be launched from exactly one place, the serializer"
done

for process_id in screenOffProcess wakeProcess; do
  qml_block "id: $process_id" | rg -q 'root\.flushDisplayState\(\)' ||
    fail "$process_id.onExited must flush a display state left pending while it ran"
done

pass "blank and wake are serialized through one wanted state that survives either process being busy"

# Locking already blanks the screens through its own service. When the lock
# is due at or before the screen-off deadline, launching our own blank first
# would race the lock service's independent wake path with a process it
# doesn't know about, so screen-off must be skipped everywhere it could fire.
rg -q 'screenOffSubsumedByLock: root\.lockOnIdle && root\.screenOffDelaySeconds >= root\.lockDelaySeconds' "$service" ||
  fail "screenOffSubsumedByLock must compare against the lock's own delay"

subsumption_guards=$(rg -c '!root\.screenOffSubsumedByLock' "$service")
((subsumption_guards == 5)) ||
  fail "startIdleCycle, both screen-off timers, and both switch handlers must all check screenOffSubsumedByLock"

pass "screen-off is skipped everywhere the lock is due at or before its own deadline"

# screenOffTimeoutSeconds is a raw config value and can be configured to 0,
# unlike the shared idleSchedule() deadline math which already clamps this.
# A zero rearm interval would fire on every event loop tick, blanking the
# display again the instant it wakes.
rg -q 'screenOffRearmSeconds: Math\.max\(1, screenOffTimeoutSeconds\)' "$service" ||
  fail "screenOffRearmSeconds must clamp a configured zero screenOff timeout to 1s"
qml_block 'id: screenOffRearmTimer' | rg -q 'interval: root\.screenOffRearmSeconds \* 1000' ||
  fail "screenOffRearmTimer must use the clamped screenOffRearmSeconds, not the raw timeout"
pass "the screen-off rearm timer clamps a configured zero timeout instead of firing every tick"

# ext-idle-notify only fires "resumed" when leaving the idle state, and the
# screensaver's launch activity can spend the main monitor's transition before
# a later blank -- mouse input would then leave the panels dark until the main
# monitor re-idled. A second 1s monitor covers that. It has to be armed for the
# whole cycle, not just while the screens are off: it needs a second of quiet
# to go idle before it has a resumed edge to give, and spending that second
# after the blank would miss input landing inside it. Source-level checks.
rg -q 'id: screenOffActivityMonitor' "$service" ||
  fail "a dedicated idle monitor must watch for input while the screens are dark"
rg -q 'enabled: root\.idleEnabled && root\.idledThisCycle' "$service" ||
  fail "the screen-off watcher must be armed for the whole cycle so it is already idle when a delayed blank lands"
rg -q 'if \(isIdle \|\| !root\.idleEnabled \|\| !root\.idledThisCycle \|\| !root\.screenOffThisCycle\) return' "$service" ||
  fail "the screen-off watcher must re-check every term of its own binding, including the one that disables it"
rg -A2 'screen-off-activity' "$service" | rg -q 'root\.handleActiveSignal\(\)' ||
  fail "dark-screen input must route through handleActiveSignal, not wake the screens directly"
pass "input while the screens are dark wakes them through a dedicated 1s idle monitor"

# Screen-off can legitimately fire before the lock (not subsumed), so a blank
# can still be finishing in the background when lockSystem() hands display
# ownership to the lock service. Without disowning the wanted display state
# here, that blank's own exit would drive the displays through the lock screen.
qml_block 'function lockSystem(reason)' | rg -q 'root\.pendingDisplayState = ""' ||
  fail "lockSystem() must disown the wanted display state, not just this cycle's screen-off ownership"
pass "locking disowns a display state left wanted by a screen-off blank that outlives it"

# The lock service starts its own independent wake with no way to know a
# screen-off blank from here is still in flight; if that wake finishes first,
# the stale blank disabling DPMS afterward would leave the unlock screen
# dark. lockSystem() must defer the actual lock until the blank exits instead
# of racing it, and screenOffProcess.onExited must flush that deferred lock.
qml_block 'function lockSystem(reason)' | rg -q 'if \(screenOffProcess\.running\) \{' ||
  fail "lockSystem() must defer locking while a screen-off blank is still running"
qml_block 'function lockSystem(reason)' | rg -q 'root\.pendingLockReason = reason \|\| "requested"' ||
  fail "lockSystem() must record the reason before deferring"
rg -q 'function flushPendingLock\(\)' "$service" ||
  fail "flushPendingLock() must exist to fire a lock deferred by an in-flight blank"
qml_block 'id: screenOffProcess' | rg -q 'root\.flushPendingLock\(\)' ||
  fail "screenOffProcess.onExited must flush a deferred lock, not just a deferred wake"
pass "locking waits for an in-flight screen-off blank instead of racing the lock service's own wake"

# A deferred lock is still just a decision, not yet a running process --
# cancelIdleCycle() must disown it like every other piece of cycle state, so
# activity or Stay Awake during the defer window doesn't lock anyway once the
# blank happens to finish. Dropping it has to hand the displays back too:
# lockSystem() disowned them expecting that lock to arrive, and its own wake
# is gated on idledThisCycle, which lockSystem() already cleared.
rg -q 'function cancelPendingLock\(\)' "$service" ||
  fail "one helper must own dropping a deferred lock, so every door does it the same way"
qml_block 'function cancelPendingLock()' | rg -q 'wakeScreens\(\)' ||
  fail "cancelling a deferred lock must wake the screens it was going to take over"

for door in 'function cancelIdleCycle(reason)' 'onLockOnIdleChanged'; do
  qml_block "$door" | rg -q 'cancelPendingLock\(\)' ||
    fail "every path that drops a deferred lock must go through cancelPendingLock()"
done

reason_writes=$(rg -c 'root\.pendingLockReason = ' "$service")
((reason_writes == 3)) ||
  fail "pendingLockReason should only be written where it is deferred, flushed, and cancelled"

pass "dropping a deferred lock hands the darkening displays back instead of abandoning them"

# lockOnIdle decides screenOffSubsumedByLock too, so its handler cannot only
# touch lockTimer: flipping it re-decides whether screen-off is covered by the
# lock this cycle, and turning it off has to drop a lock the idle timeout
# already deferred behind an in-flight blank.
qml_block 'onLockOnIdleChanged' | rg -q 'syncSwitchTimer\(root\.screenOffOnIdle && !root\.screenOffSubsumedByLock, screenOffTimer' ||
  fail "onLockOnIdleChanged must resync the screen-off timer it just re-decided"
pass "flipping lock-on-idle resyncs the screen-off it subsumes"

# Screen-off can be configured ahead of the screensaver, so the activity the
# screensaver provokes when it maps can land on already-dark panels. Treating
# that as a bump would relight a screen nobody asked to wake, for a whole
# rearm period, with no one at the machine. The launch claims its own report
# and handleActiveSignal spends it instead of waking.
qml_block 'function launchScreensaver()' | rg -q 'root\.screensaverActivityExpected = true' ||
  fail "launchScreensaver() must claim the activity report its own mapping provokes"
rg -q 'if \(root\.screensaverActivityExpected\) root\.screensaverActivityExpected = false' "$service" ||
  fail "handleActiveSignal must spend the screensaver's own activity report rather than act on it"
rg -A2 'if \(root\.screensaverActivityExpected\)' "$service" | rg -q 'else if \(root\.screenOffThisCycle\) rearmScreenOff\(\)' ||
  fail "only a bump that is not the screensaver's own may relight the panels"

claim_releases=$(rg -c 'root\.screensaverActivityExpected = false' "$service")
((claim_releases == 4)) ||
  fail "an unspent claim must be released everywhere the launch it belongs to is forgotten"

pass "the screensaver's own launch activity does not relight panels screen-off just darkened"
