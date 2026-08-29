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

assertEqual(
  idle.isFirefoxFamilyPlayer({ dbusName: 'org.mpris.MediaPlayer2.firefox.instance_1_72', isPlaying: true }),
  true,
  'idle treats Firefox MPRIS as a firefox-family player'
)
assertEqual(
  idle.isFirefoxFamilyPlayer({ dbusName: 'org.mpris.MediaPlayer2.zen', desktopEntry: 'zen', isPlaying: false }),
  true,
  'idle treats Zen MPRIS as a firefox-family player'
)
assertEqual(
  idle.isFirefoxFamilyPlayer({ dbusName: 'org.mpris.MediaPlayer2.spotify', identity: 'Spotify', isPlaying: true }),
  false,
  'idle does not treat Spotify as a firefox-family player'
)
assertEqual(
  idle.isFirefoxFamilyPlayer({ dbusName: 'org.mpris.MediaPlayer2.chromium.instance123', isPlaying: true }),
  false,
  'idle does not treat Chromium as a firefox-family player'
)
assertEqual(
  idle.isFirefoxFamilyPlayer({ dbusName: 'org.mpris.MediaPlayer2.playerctld', desktopEntry: 'playerctld', isPlaying: true }),
  false,
  'idle ignores playerctld proxies'
)
assertEqual(
  idle.isFirefoxFamilyPlayer({ identity: 'Citizen Sleeper', isPlaying: true }),
  false,
  'idle does not match zen inside unrelated identity strings'
)
assertEqual(
  idle.firefoxFamilyIsPlaying([
    { dbusName: 'org.mpris.MediaPlayer2.spotify', isPlaying: true },
    { dbusName: 'org.mpris.MediaPlayer2.firefox.instance1', isPlaying: false }
  ]),
  false,
  'idle stays off when Firefox is paused even if other media is playing'
)
assertEqual(
  idle.firefoxFamilyIsPlaying([
    { dbusName: 'org.mpris.MediaPlayer2.firefox.instance1', isPlaying: true }
  ]),
  true,
  'idle reports firefox-family playback while Firefox is playing'
)
assertEqual(idle.idleEnabledAfter(true, false, false), true, 'idle runs when stay-awake is off and no media inhibit')
assertEqual(idle.idleEnabledAfter(true, true, false), false, 'idle stays off while stay-awake is on')
assertEqual(idle.idleEnabledAfter(true, false, true), false, 'idle stays off while firefox-family media is playing')
assertEqual(idle.idleEnabledAfter(false, false, false), false, 'idle stays off until stay-awake state is loaded')
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

rg -F 'IdleModel.idleEnabledAfter(stayAwakeStateLoaded, stayAwake, mediaInhibiting)' \
  "$ROOT/shell/plugins/services/idle/Service.qml" >/dev/null ||
  fail "idle service gates IdleMonitor on stay-awake and firefox-family media inhibit"

rg -F 'return root.setIdleEnabled(root.stayAwake)' \
  "$ROOT/shell/plugins/services/idle/Service.qml" >/dev/null ||
  fail "idle toggle flips stayAwake rather than the derived idleEnabled flag"

rg -F 'cancelIdleCycle("media-playing")' \
  "$ROOT/shell/plugins/services/idle/Service.qml" >/dev/null ||
  fail "idle service cancels an in-flight cycle when firefox-family media starts"

rg -F 'import Quickshell.Services.Mpris' \
  "$ROOT/shell/plugins/services/idle/Service.qml" >/dev/null ||
  fail "idle service watches MPRIS for firefox-family playback"

rg -F 'idle_inhibit = "fullscreen"' "$ROOT/default/hypr/apps/browser.lua" >/dev/null ||
  fail "firefox-based browsers inhibit idle while fullscreen"

pass "idle service wiring holds firefox-family playback off the screensaver"
