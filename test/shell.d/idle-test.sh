#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const idle = requireFromRoot('shell/plugins/services/idle/IdleModel.js')

assertDeepEqual(idle.stayAwakeState('no', 1000), { enabled: false, until: 0 }, 'missing state allows idle')
assertDeepEqual(idle.stayAwakeState('yes:', 1000), { enabled: true, until: 0 }, 'legacy empty state stays awake indefinitely')
assertDeepEqual(idle.stayAwakeState('yes:2000', 1000), { enabled: true, until: 2000 }, 'future deadline survives reload')
assertDeepEqual(idle.stayAwakeState('yes:1000', 1000), { enabled: false, until: 0 }, 'deadline expires at boundary')
assertDeepEqual(idle.stayAwakeState('yes:999', 1000), { enabled: false, until: 0 }, 'past deadline allows idle')
assertDeepEqual(idle.stayAwakeState('yes:invalid', 1000), { enabled: false, until: 0 }, 'invalid deadline allows idle')

for (const raw of ['yes:1e300', 'yes:Infinity', 'yes:0x1000', 'yes:2000.5', 'yes: 2000 ', 'yes:\n', 'yes:2000\nno', 'yes:2000' + '\n'.repeat(70), 'yes:86401001']) {
  assertDeepEqual(idle.stayAwakeState(raw, 1000), { enabled: false, until: 0 }, 'malformed or excessive deadline allows idle: ' + JSON.stringify(raw))
}
assertDeepEqual(idle.stayAwakeState('yes:2000\n', 1000), { enabled: true, until: 2000 }, 'a trailing newline is allowed')
assertDeepEqual(idle.stayAwakeState('yes:12345:6789:1234\n', 1000), { enabled: true, until: 0 }, 'update ownership tokens still inhibit idle')
assertEqual(idle.stayAwakeDeadline(3600, 1000), 3601000, 'one hour produces an absolute deadline')
assertEqual(idle.stayAwakeDeadline(86400, 1000), 86401000, 'one day is the maximum duration')
for (const seconds of [0, -1, 1.5, 86401, Infinity, NaN, 1e300, '$(touch /tmp/should-not-exist)']) {
  assertEqual(idle.stayAwakeDeadline(seconds, 1000), 0, 'invalid duration is rejected: ' + String(seconds))
}

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

# Expired deadlines need no cleanup process: both the CLI and the shell ignore them.
printf '1' > "$test_home/.local/state/omarchy/indicators/stay-awake"
HOME="$test_home" "$ROOT/bin/omarchy-toggle-idle" status | jq -e '.enabled == false' >/dev/null || fail "Expired state allows idle in the CLI"
HOME="$test_home" "$ROOT/bin/omarchy-toggle-idle" >/dev/null
[[ ! -s $test_home/.local/state/omarchy/indicators/stay-awake ]] || fail "Toggle from expired state enables indefinitely"

state_file="$test_home/.local/state/omarchy/indicators/stay-awake"
victim="$test_tmp/preserve-me"
printf 'unchanged' > "$victim"
rm "$state_file"
ln -s "$victim" "$state_file"
HOME="$test_home" "$ROOT/bin/omarchy-toggle-idle" stay-awake >/dev/null
[[ $(cat "$victim") == "unchanged" && ! -L $state_file ]] || fail "State writes replace symlinks without truncating targets"

rm "$state_file"
mkdir "$state_file"
if HOME="$test_home" "$ROOT/bin/omarchy-toggle-idle" stay-awake >/dev/null 2>&1; then
  fail "A failed state write must return failure"
fi
[[ -z $(find "${state_file%/*}" -name '.stay-awake.*' -print) ]] || fail "Failed writes clean up temporary files"

pass "Stay Awake toggle persists state atomically without reentrant shell IPC"
