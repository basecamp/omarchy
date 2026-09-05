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

assertEqual(idle.screensaverIdFromConfig(undefined), '', 'idle treats a missing screensaverId as no selection')
assertEqual(idle.screensaverIdFromConfig('   '), '', 'idle treats a blank screensaverId as no selection')
assertEqual(idle.screensaverIdFromConfig(42), '', 'idle treats a non-string screensaverId as no selection')
assertEqual(idle.screensaverIdFromConfig(' acme.saver '), 'acme.saver', 'idle trims the configured screensaverId')

const launch = idle.screensaverLaunch('/plugins/acme.saver/bin/launch')
assertDeepEqual(
  launch.args,
  ['omarchy-idle-screensaver', '/plugins/acme.saver/bin/launch'],
  'idle passes the screensaver launcher as an argument, never spliced into the script'
)
assert(launch.command.indexOf('isLocked') !== -1, 'idle screensaver launch keeps the isLocked guard')
assert(launch.command.indexOf('omarchy-launch-screensaver') !== -1, 'idle screensaver launch keeps the built-in fallback')
assertDeepEqual(
  idle.screensaverLaunch('').args,
  ['omarchy-idle-screensaver', ''],
  'idle screensaver launch tolerates no selected launcher'
)
JS

# Exercise the exact launch script the idle service hands to bash, with the
# launcher path in $1 the way Service.qml passes it. omarchy-shell is stubbed
# so the isLocked guard can be steered from the environment.
launch_script=$(node -e '
  const idle = require(process.argv[1] + "/shell/plugins/services/idle/IdleModel.js")
  process.stdout.write(idle.screensaverLaunch("x").command)
' "$ROOT")

guard_tmp=$(mktemp -d)
trap 'rm -rf "$guard_tmp"' EXIT

mkdir -p "$guard_tmp/bin"
cat >"$guard_tmp/bin/omarchy-shell" <<'SH'
#!/bin/bash
echo "${OMARCHY_TEST_IS_LOCKED:-false}"
SH
cat >"$guard_tmp/bin/omarchy-launch-screensaver" <<'SH'
#!/bin/bash
touch "$OMARCHY_TEST_BUILTIN_RAN"
SH
cat >"$guard_tmp/bin/omarchy-toggle-enabled" <<'SH'
#!/bin/bash
[[ ${OMARCHY_TEST_SCREENSAVER_OFF:-0} == "1" ]]
SH
chmod +x "$guard_tmp/bin"/*

builtin_marker="$guard_tmp/builtin-ran"
plugin_marker="$guard_tmp/plugin-ran"

cat >"$guard_tmp/plugin launcher" <<SH
#!/bin/bash
touch "$plugin_marker"
SH
chmod +x "$guard_tmp/plugin launcher"

run_launch_script() {
  rm -f "$builtin_marker" "$plugin_marker"
  PATH="$guard_tmp/bin:$PATH" OMARCHY_TEST_BUILTIN_RAN="$builtin_marker" \
    OMARCHY_TEST_IS_LOCKED="$1" bash -c "$launch_script" omarchy-idle-screensaver "$2"
}

run_launch_script false ""
[[ -e $builtin_marker ]] || fail "launch script without a selection runs the built-in screensaver"
pass "launch script without a selection runs the built-in screensaver"

run_launch_script false "$guard_tmp/plugin launcher"
[[ -e $plugin_marker && ! -e $builtin_marker ]] || fail "launch script runs the selected launcher instead of the built-in"
pass "launch script runs the selected launcher instead of the built-in"

run_launch_script false "$guard_tmp/missing-launcher"
[[ -e $builtin_marker && ! -e $plugin_marker ]] || fail "launch script falls back to the built-in when the launcher is missing"
pass "launch script falls back to the built-in when the launcher is missing"

chmod 644 "$guard_tmp/plugin launcher"
run_launch_script false "$guard_tmp/plugin launcher"
[[ -e $builtin_marker && ! -e $plugin_marker ]] || fail "launch script falls back to the built-in when the launcher is not executable"
pass "launch script falls back to the built-in when the launcher is not executable"
chmod 755 "$guard_tmp/plugin launcher"

run_launch_script true "$guard_tmp/plugin launcher"
[[ ! -e $plugin_marker && ! -e $builtin_marker ]] || fail "locked session launches no screensaver at all"
run_launch_script true ""
[[ ! -e $builtin_marker ]] || fail "locked session launches no built-in screensaver either"
pass "locked session launches no screensaver at all"

# The screensaver-off toggle reaches plugin screensavers through the launch
# script, so a plugin launcher cannot run while the toggle is on. The built-in
# fallback enforces the toggle itself, exactly as it did before.
OMARCHY_TEST_SCREENSAVER_OFF=1 run_launch_script false "$guard_tmp/plugin launcher"
[[ ! -e $plugin_marker ]] || fail "screensaver-off toggle keeps the plugin launcher from running"
pass "screensaver-off toggle keeps the plugin launcher from running"

# The launcher path is an argv element, not part of the script, so a hostile
# path cannot break out of the guard: it fails the -x test and falls back.
run_launch_script false '"; touch '"$guard_tmp"'/escaped; #'
[[ ! -e $guard_tmp/escaped ]] || fail "launch script never evaluates the launcher path as shell"
[[ -e $builtin_marker ]] || fail "hostile launcher path still falls back to the built-in"
pass "launch script never evaluates the launcher path as shell"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp" "$guard_tmp"' EXIT

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
