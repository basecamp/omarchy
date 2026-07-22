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
JS

require_command python3

ROOT="$ROOT" python3 <<'PY'
import importlib.util
import io
import os
from pathlib import Path
from types import SimpleNamespace

helper_path = Path(os.environ["ROOT"]) / "shell/plugins/services/idle/scripts/gamepad_activity.py"
spec = importlib.util.spec_from_file_location("gamepad_activity", helper_path)
gamepad = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gamepad)


def check(condition, description):
  if not condition:
    raise AssertionError(description)
  print(f"ok - {description}")


check(
  gamepad.has_gamepad_buttons({gamepad.EV_KEY: [30, gamepad.BTN_JOYSTICK]}),
  "idle recognizes gamepad button capabilities",
)
check(
  not gamepad.has_gamepad_buttons({gamepad.EV_KEY: [1, 30, 57]}),
  "idle does not classify a keyboard as a gamepad",
)

axis = SimpleNamespace(value=0, min=-32768, max=32767, flat=500)
activity_filter = gamepad.ActivityFilter({0: axis})
check(
  not activity_filter.accepts(gamepad.EV_ABS, 0, 800),
  "idle filters analog stick drift",
)
check(
  activity_filter.accepts(gamepad.EV_ABS, 0, 1400),
  "idle accepts cumulative intentional axis movement",
)
check(activity_filter.accepts(gamepad.EV_KEY, 304, 1), "idle accepts gamepad buttons")
check(activity_filter.accepts(gamepad.EV_REL, 0, 1), "idle accepts relative gamepad input")

timestamps = iter([10.0, 10.5, 11.1])
output = io.StringIO()
reporter = gamepad.ActivityReporter(clock=lambda: next(timestamps), stream=output)
check(reporter.report(), "idle reports initial gamepad activity")
check(not reporter.report(), "idle throttles repeated gamepad activity")
check(reporter.report(), "idle resumes gamepad activity reports after throttle")
check(output.getvalue() == "activity\nactivity\n", "idle emits the shell activity protocol")
PY

if ! rg -qx 'python-evdev' "$ROOT/install/omarchy-base.packages"; then
  fail "Gamepad activity dependency is in the base package list"
fi

if ! rg -q 'enabled: root.idleEnabled && !root.idleResetPending' "$ROOT/shell/plugins/services/idle/Service.qml"; then
  fail "Gamepad activity resets the idle monitor"
fi

if ! rg -q 'idle/scripts/gamepad_activity.py' "$ROOT/shell/plugins/services/idle/Service.qml"; then
  fail "Gamepad activity helper is started by the idle service"
fi

if ! rg -q 'function activity\(\): string' "$ROOT/shell/plugins/services/idle/Service.qml"; then
  fail "Idle activity is available over shell IPC"
fi

pass "Gamepad activity is wired into the idle service"

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
