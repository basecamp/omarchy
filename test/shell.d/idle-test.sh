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

assertEqual(idle.inhibitorCountFromValue('2'), 2, 'idle parses the D-Bus inhibitor count')
assertEqual(idle.inhibitorCountFromValue('1.9'), 1, 'idle floors a fractional inhibitor count')
assertEqual(idle.inhibitorCountFromValue('-1'), 0, 'idle floors a negative inhibitor count to zero')
assertEqual(idle.inhibitorCountFromValue('nope'), 0, 'idle floors an unparsable inhibitor count to zero')
assertEqual(idle.inhibitorCountFromValue(undefined), 0, 'idle floors a missing inhibitor count to zero')
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

idle_service="$ROOT/shell/plugins/services/idle/Service.qml"

grep -Fq 'root.dbusInhibitors === 0' "$idle_service" ||
  fail "idleEnabled no longer requires D-Bus inhibitors to be clear (#6475 regression)"
grep -Fq 'function setDbusInhibitors(count: string): string' "$idle_service" ||
  fail "idle service dropped the setDbusInhibitors IPC method the bridge depends on"
grep -Fq 'function applyDbusInhibitors(value)' "$idle_service" ||
  fail "idle service dropped applyDbusInhibitors"
pass "idle service tracks D-Bus inhibitors and exposes them over IPC"

bridge_bin="$ROOT/bin/omarchy-system-idle-inhibit-bridge"
[[ -x $bridge_bin ]] || fail "omarchy-system-idle-inhibit-bridge must be executable"

require_command python3
python3 -m py_compile "$bridge_bin" ||
  fail "omarchy-system-idle-inhibit-bridge has a syntax error"

grep -Fq 'BUS_NAME = "org.freedesktop.ScreenSaver"' "$bridge_bin" ||
  fail "idle inhibit bridge must own org.freedesktop.ScreenSaver"
grep -Fq 'setDbusInhibitors' "$bridge_bin" ||
  fail "idle inhibit bridge no longer reports state to the idle service"
grep -Fq 'sync_idle_service(0)' "$bridge_bin" ||
  fail "idle inhibit bridge must reset the idle service to zero on (re)start, or a crash while inhibited leaves idling stuck disabled"
pass "D-Bus idle inhibit bridge owns org.freedesktop.ScreenSaver and reports to the idle service"
