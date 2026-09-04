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
assertEqual(audio.outputVolumeName(0.5, true), 'Muted', 'audio labels muted output')

assertDeepEqual(audio.parseSinkAvailability('alsa_output\t1\nhdmi_output\t0\n'), { alsa_output: true, hdmi_output: false }, 'audio parses sink availability')
assertEqual(audio.friendlyDeviceLabel('Built-in Audio Speakers Output'), 'Speakers', 'audio cleans device labels')
assertEqual(
  audio.nodeLabel({ ready: true, properties: { 'node.nick': 'Built-in Audio Microphones Input' }, name: 'alsa_input' }),
  'Microphone',
  'audio chooses friendly node labels'
)
assertEqual(
  audio.nodeLabel({
    ready: true,
    name: 'alsa_input.usb-SteelSeries.mono-chat',
    nickname: 'SteelSeries Arctis 7',
    description: 'SteelSeries Arctis 7 Chat',
    properties: { 'node.nick': 'SteelSeries Arctis 7', 'device.profile.description': 'Chat' }
  }),
  'SteelSeries Arctis 7 Chat',
  'audio prefers a descriptive input label over its nickname'
)
assertEqual(
  audio.nodeLabel({
    ready: true,
    name: 'alsa_output.usb-SteelSeries.stereo-game',
    nickname: 'USB Audio #1',
    description: 'SteelSeries Arctis 7 Game',
    properties: { 'node.nick': 'USB Audio #1', 'device.profile.description': 'Game' }
  }),
  'SteelSeries Arctis 7 Game',
  'audio keeps distinct profiles of the same output device'
)
assertEqual(
  audio.nodeLabel({
    ready: true,
    description: 'SteelSeries Arctis 7',
    properties: { 'device.profile.description': 'Game' }
  }),
  'SteelSeries Arctis 7 Game',
  'audio adds a missing profile to a generic node description'
)
assertEqual(
  audio.nodeLabel({
    ready: true,
    properties: {
      'node.nick': 'USB Audio #1',
      'device.description': 'SteelSeries Arctis 7',
      'device.profile.description': 'Game'
    }
  }),
  'SteelSeries Arctis 7 Game',
  'audio reconstructs a descriptive label from device and profile metadata'
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

test_tmp=$(mktemp -d)
trap 'rm -rf -- "$test_tmp"' EXIT
mock_bin="$test_tmp/bin"
call_log="$test_tmp/calls.log"
mkdir -p "$mock_bin"

cat >"$mock_bin/timeout" <<'SH'
#!/bin/bash
shift
exec "$@"
SH

cat >"$mock_bin/wpctl" <<'SH'
#!/bin/bash
printf 'wpctl %s\n' "$*" >>"$AUDIO_TEST_LOG"
SH

cat >"$mock_bin/pactl" <<'SH'
#!/bin/bash
printf 'pactl %s\n' "$*" >>"$AUDIO_TEST_LOG"

if [[ $1 == "list" && $2 == "sink-inputs" ]]; then
  cat <<'EOF'
Sink Input #11864
        application.name = "cliamp"
Sink Input #11865
        node.name = "omarchy_speaker_tuning.capture"
Sink Input #11866
        application.name = "EasyEffects"
EOF
fi
SH

chmod +x "$mock_bin/timeout" "$mock_bin/wpctl" "$mock_bin/pactl"

AUDIO_TEST_LOG="$call_log" PATH="$mock_bin:/usr/bin" \
  "$ROOT/bin/omarchy-audio-output-set-default" 4735 \
  alsa_output.usb-SteelSeries.stereo-game

grep -Fx 'wpctl set-default 4735' "$call_log" >/dev/null ||
  fail "audio output switch updates the PipeWire default"
grep -Fx 'pactl set-default-sink alsa_output.usb-SteelSeries.stereo-game' "$call_log" >/dev/null ||
  fail "audio output switch updates the PulseAudio default"
grep -Fx 'pactl move-sink-input 11864 alsa_output.usb-SteelSeries.stereo-game' "$call_log" >/dev/null ||
  fail "audio output switch moves active application streams"
if grep -Eq 'move-sink-input (11865|11866)' "$call_log"; then
  fail "audio output switch moves DSP streams"
fi
pass "audio output switch preserves playback without moving DSP streams"
