#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const audio = requireFromRoot('shell/plugins/panels/audio/Model.js')

assert(audio.isPlaybackStream({ isStream: true, isSink: true }), 'audio detects sink-backed playback streams')
assert(audio.isPlaybackStream({ isStream: true, type: 'Stream/Output/Audio' }), 'audio detects typed playback streams')
assert(!audio.isPlaybackStream({ isStream: false, isSink: true }), 'audio rejects non-stream playback nodes')
assert(audio.isAudioSource({ audio: {} }), 'audio detects nodes with audio as sources')
assert(audio.isAudioSource({ type: 'Audio/Source' }), 'audio detects typed source nodes')

assertEqual(audio.outputVolumeName(0, false), 'Silenced', 'audio labels silent output')
assertEqual(audio.outputVolumeName(0.9, false), 'Party mode', 'audio labels loud output')
assertEqual(audio.outputVolumeName(1.19, false), 'Concert hall', 'audio keeps the standard boosted label below 120 percent')
assertEqual(audio.outputVolumeName(1.2, false), 'Blowout alert!', 'audio labels volume at 120 percent')
assertEqual(audio.outputVolumeName(1.5, false), 'Blowout alert!', 'audio keeps the 120 percent label at higher volumes')
assertEqual(audio.outputVolumeName(0.5, true), 'Muted', 'audio labels muted output')

assertDeepEqual(audio.parseSinkAvailability('alsa_output\t1\nhdmi_output\t0\n'), { alsa_output: true, hdmi_output: false }, 'audio parses sink availability')
assertEqual(audio.friendlyDeviceLabel('Built-in Audio Speakers Output'), 'Speakers', 'audio cleans device labels')
assertEqual(
  audio.nodeLabel({ ready: true, properties: { 'node.nick': 'Built-in Audio Microphones Input' }, name: 'alsa_input' }),
  'Microphone',
  'audio chooses friendly node labels'
)

const headphones = { ready: true, name: 'bluez_output.airpods', properties: { 'device.product.name': 'AirPods Headphones' } }
assert(audio.isHeadphones(headphones), 'audio detects headphone devices')
assertEqual(audio.sinkGlyph(headphones), '󰋋', 'audio uses headphone sink glyph')
assert(audio.sourceGlyph({ ready: true, properties: { 'device.icon-name': 'camera-webcam' } }).length > 0, 'audio maps webcam source glyph')

assertEqual(audio.friendlyStreamLabel('spotify'), 'Spotify', 'audio normalizes known stream labels')
assert(audio.streamRepresentsMprisPlayer('Chromium', 'Chromium Browser'), 'audio matches related stream and MPRIS labels')

const players = [
  { identity: 'Spotify', canPlay: true, isPlaying: true, dbusName: 'org.mpris.MediaPlayer2.spotify' },
  { identity: 'Chromium', canPlay: true, isPlaying: false, dbusName: 'org.mpris.MediaPlayer2.chromium' }
]
const streams = [
  { ready: true, properties: { 'application.name': 'Chromium' } },
  { ready: true, properties: { 'application.name': 'audio-src' } }
]

assertEqual(audio.matchingMprisStreamLabel('Chromium', players), 'Chromium', 'audio finds matching MPRIS labels')
assertEqual(audio.unmatchedMprisStreamLabel('audio-src', players, streams), 'Spotify', 'audio uses unmatched MPRIS player for generic streams')
assertEqual(audio.streamLabel(streams[1], players, streams), 'Spotify', 'audio labels generic streams from MPRIS')
assert(audio.streamRepresentsPlayer(streams[1], players[0], players, streams), 'audio links generic streams to active player')
JS

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp"/{bin,state/omarchy}

HOME="$tmp" XDG_STATE_HOME="$tmp/state" OMARCHY_PATH="$ROOT" lua <<'LUA'
require("default.hypr.helpers")

o.audio({ max_volume = 150 })

local file = assert(io.open(os.getenv("XDG_STATE_HOME") .. "/omarchy/audio-max-volume"))
assert(file:read("*l") == "150")
file:close()

assert(not pcall(o.audio, { max_volume = 0 }))
assert(not pcall(o.audio, { max_volume = "150" }))
assert(not pcall(o.audio, { max_volume = 150.5 }))
LUA

pass "audio validates and publishes max volume"

printf '#!/bin/bash\necho test_sink\n' >"$tmp/bin/omarchy-audio-output-sink"
printf '#!/bin/bash\n:\n' >"$tmp/bin/omarchy-osd"

cat >"$tmp/bin/pactl" <<'SH'
#!/bin/bash
case "$1" in
  get-sink-volume) printf 'Volume: %s%%\n' "$(<"$TEST_VOLUME")" ;;
  get-sink-mute) echo "Mute: no" ;;
  set-sink-mute) ;;
  set-sink-volume) echo "${3%%%}" >"$TEST_VOLUME" ;;
esac
SH

chmod +x "$tmp/bin/"*

export TEST_VOLUME="$tmp/volume"
export XDG_STATE_HOME="$tmp/state"
export PATH="$tmp/bin:$PATH"

echo 148 >"$TEST_VOLUME"
"$ROOT/bin/omarchy-audio-output-volume" raise
[[ $(<"$TEST_VOLUME") == 150 ]] || fail "audio respects configured max volume"
pass "audio respects configured max volume"

rm "$tmp/state/omarchy/audio-max-volume"
echo 98 >"$TEST_VOLUME"
"$ROOT/bin/omarchy-audio-output-volume" raise
[[ $(<"$TEST_VOLUME") == 100 ]] || fail "audio defaults max volume to 100 percent"
pass "audio defaults max volume to 100 percent"
