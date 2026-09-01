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

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin"

cat >"$tmp_dir/bin/wpctl" <<'EOF'
#!/bin/bash
printf 'wpctl %s\n' "$*" >>"$AUDIO_CALLS"
EOF
chmod +x "$tmp_dir/bin/wpctl"

cat >"$tmp_dir/bin/pactl" <<'EOF'
#!/bin/bash

printf 'pactl %s\n' "$*" >>"$AUDIO_CALLS"

if [[ $* == "--format=json list sources" ]]; then
  polls=0
  [[ ! -f $AUDIO_SOURCE_POLLS ]] || polls=$(<"$AUDIO_SOURCE_POLLS")
  (( polls += 1 ))
  printf '%s\n' "$polls" >"$AUDIO_SOURCE_POLLS"
  if (( polls >= ${AUDIO_SOURCE_READY_AFTER:-3} )); then
    printf '[{"name":"bluez_input.AA:BB:CC:DD:EE:FF","properties":{"device.name":"bluez_card.AA_BB_CC_DD_EE_FF","media.class":"Audio/Source","bluez5.loopback":"true"}},{"name":"bluez_output.AA_BB_CC_DD_EE_FF.1.monitor","properties":{"device.name":"bluez_card.AA_BB_CC_DD_EE_FF","media.class":"Audio/Sink","device.class":"monitor"}},{"name":"bluez_input.AA_BB_CC_DD_EE_FF.0","properties":{"device.name":"bluez_card.AA_BB_CC_DD_EE_FF","media.class":"Audio/Source","bluez5.loopback":"false"}}]\n'
  else
    printf '[{"name":"bluez_input.AA:BB:CC:DD:EE:FF","properties":{"device.name":"bluez_card.AA_BB_CC_DD_EE_FF","media.class":"Audio/Source","bluez5.loopback":"true"}},{"name":"bluez_output.AA_BB_CC_DD_EE_FF.1.monitor","properties":{"device.name":"bluez_card.AA_BB_CC_DD_EE_FF","media.class":"Audio/Sink","device.class":"monitor"}}]\n'
  fi
elif [[ $* == "list short source-outputs" ]]; then
  printf '71\tPipeWire\n'
elif [[ $1 == "move-source-output" && $3 == bluez_input.* ]]; then
  polls=0
  [[ ! -f $AUDIO_SOURCE_POLLS ]] || polls=$(<"$AUDIO_SOURCE_POLLS")
  if (( polls < ${AUDIO_SOURCE_READY_AFTER:-3} )); then
    printf 'early\n' >"$AUDIO_EARLY_MOVE"
    exit 1
  fi
  attempts=0
  [[ ! -f $AUDIO_ATTEMPTS ]] || attempts=$(<"$AUDIO_ATTEMPTS")
  (( attempts += 1 ))
  printf '%s\n' "$attempts" >"$AUDIO_ATTEMPTS"
elif [[ $1 == "move-source-output" && ${AUDIO_ALSA_MOVE_FAIL:-0} == "1" ]]; then
  exit 1
fi
EOF
chmod +x "$tmp_dir/bin/pactl"

cat >"$tmp_dir/bin/pw-record" <<'EOF'
#!/bin/bash
printf 'pw-record %s\n' "$*" >>"$AUDIO_CALLS"
trap 'exit 0' TERM INT
while true; do sleep 1; done
EOF
chmod +x "$tmp_dir/bin/pw-record"

cat >"$tmp_dir/bin/omarchy-notification-send" <<'EOF'
#!/bin/bash
printf 'omarchy-notification-send %s\n' "$*" >>"$AUDIO_CALLS"
EOF
chmod +x "$tmp_dir/bin/omarchy-notification-send"

audio_calls="$tmp_dir/calls"
audio_attempts="$tmp_dir/attempts"
audio_source_polls="$tmp_dir/source-polls"
audio_early_move="$tmp_dir/early-move"

run_input_switch() {
  AUDIO_CALLS="$audio_calls" AUDIO_ATTEMPTS="$audio_attempts" AUDIO_SOURCE_POLLS="$audio_source_polls" \
    AUDIO_EARLY_MOVE="$audio_early_move" \
    AUDIO_SOURCE_READY_AFTER="${AUDIO_SOURCE_READY_AFTER:-3}" AUDIO_ALSA_MOVE_FAIL="${AUDIO_ALSA_MOVE_FAIL:-0}" \
    PATH="$tmp_dir/bin:$PATH" \
    "$ROOT/bin/omarchy-audio-input-set-default" "$@"
}

: >"$audio_calls"
run_input_switch 43 bluez_input.AA:BB:CC:DD:EE:FF
[[ $(<"$audio_attempts") == "1" ]] ||
  fail "audio moves the active stream once after Bluetooth is ready" "$(<"$audio_calls")"
[[ ! -e $audio_early_move ]] ||
  fail "audio does not move active streams during the Bluetooth graph rebuild" "$(<"$audio_calls")"
! grep -Fq 'set-card-profile' "$audio_calls" ||
  fail "audio leaves Bluetooth profile selection and restoration to WirePlumber" "$(<"$audio_calls")"
pass "audio waits for the physical Bluetooth source without forcing a profile"

: >"$audio_calls"
: >"$audio_attempts"
rm -f "$audio_source_polls" "$audio_early_move"
if AUDIO_SOURCE_READY_AFTER=99 run_input_switch 43 bluez_input.AA:BB:CC:DD:EE:FF 2>/dev/null; then
  fail "audio reports an exhausted Bluetooth capture move"
fi
[[ ! -s $audio_attempts ]] ||
  fail "audio leaves active streams untouched when Bluetooth readiness is exhausted" "$(<"$audio_calls")"
grep -Fq 'omarchy-notification-send -u critical Bluetooth microphone unavailable' "$audio_calls" ||
  fail "audio notifies when Bluetooth capture routing is exhausted" "$(<"$audio_calls")"
pass "audio reports an exhausted Bluetooth capture move after bounded retries"

: >"$audio_calls"
run_input_switch 44 alsa_input.usb-Generic_USB_Audio-00.mono-fallback
[[ $(grep -Fc 'pactl move-source-output 71 alsa_input.usb-Generic_USB_Audio-00.mono-fallback' "$audio_calls") == "1" ]] ||
  fail "audio moves an ordinary capture stream once" "$(<"$audio_calls")"
pass "audio moves an ordinary capture stream once"

if ! AUDIO_ALSA_MOVE_FAIL=1 run_input_switch 44 alsa_input.usb-Generic_USB_Audio-00.mono-fallback; then
  fail "audio keeps ordinary capture stream moves best effort"
fi
pass "audio keeps ordinary capture stream moves best effort"
