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
assertEqual(audio.nodeSerial({ ready: true, properties: { 'object.serial': 384 } }), '384', 'audio reads PipeWire object serials')
assertEqual(audio.nodeSerial({ ready: false, properties: { 'object.serial': 384 } }), '', 'audio ignores unbound PipeWire object serials')
const defaultOutput = { ready: true, properties: { 'object.serial': 85, 'node.nick': 'Laptop Speakers' } }
const routedOutput = { ready: true, properties: { 'object.serial': 91, 'node.nick': 'USB Headset' } }
const hdmiOutput = { ready: true, properties: { 'object.serial': 120, 'node.nick': 'HDMI Display' } }
assertDeepEqual(
  audio.streamOutputOptions([routedOutput, defaultOutput, hdmiOutput], defaultOutput),
  [
    { value: 'default:85', label: 'Follow default output' },
    { value: 'override:85', label: 'Pin to Laptop Speakers' },
    { value: 'override:91', label: 'USB Headset' },
    { value: 'override:120', label: 'HDMI Display' }
  ],
  'audio distinguishes following from pinning to the current default'
)
assertDeepEqual(audio.parseStreamOutputOption('default:85'), { mode: 'default', sink: '85' }, 'audio parses a default-following route')
assertDeepEqual(audio.parseStreamOutputOption('override:91'), { mode: 'override', sink: '91' }, 'audio parses an explicit route')
assertDeepEqual(audio.parseStreamOutputOption('speaker'), { mode: '', sink: '' }, 'audio rejects malformed route options')

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

cat >"$tmp_dir/sink-inputs.json" <<'JSON'
[
  {"index": 384, "sink": 85, "properties": {"application.name": "Spotify", "object.id": 102}},
  {"index": 512, "sink": 91, "properties": {"application.name": "Browser", "object.id": 103}},
  {"index": 513, "sink": 85, "properties": {"application.name": "Pinned", "object.id": 106}},
  {"index": 514, "sink": 85, "properties": {"application.name": "Legacy"}},
  {"index": 600, "sink": 85, "properties": {"application.name": "EasyEffects", "object.id": 104}},
  {"index": 700, "sink": 85, "properties": {"object.id": 105}}
]
JSON

cat >"$tmp_dir/sinks.json" <<'JSON'
[
  {"index": 85, "name": "old-default", "properties": {"object.id": 201}},
  {"index": 91, "name": "new-default", "properties": {"object.id": 202}}
]
JSON

cat >"$tmp_dir/bin/pactl" <<'EOF'
#!/bin/bash

if [[ $1 == "-f" && $2 == "json" && $3 == "list" ]]; then
  case "$4" in
    sink-inputs) cat "$AUDIO_SINK_INPUTS_FIXTURE" ;;
    sinks) cat "$AUDIO_SINKS_FIXTURE" ;;
    *) exit 1 ;;
  esac
elif [[ $1 == "get-default-sink" ]]; then
  printf '%s\n' "${AUDIO_DEFAULT_SINK:-old-default}"
elif [[ $1 == "set-default-sink" ]]; then
  printf '<%s>\n' "$@" >>"$AUDIO_CALLS_LOG"
elif [[ $1 == "move-sink-input" ]]; then
  printf '<%s>\n' "$@" >>"$AUDIO_CALLS_LOG"
  [[ ${AUDIO_MOVE_FAIL:-0} == "0" ]]
else
  exit 1
fi
EOF
chmod +x "$tmp_dir/bin/pactl"

cat >"$tmp_dir/bin/wpctl" <<'EOF'
#!/bin/bash

printf '<wpctl:%s>\n' "$*" >>"$AUDIO_CALLS_LOG"
EOF
chmod +x "$tmp_dir/bin/wpctl"

cat >"$tmp_dir/bin/pw-metadata" <<'EOF'
#!/bin/bash

if [[ $# == 2 && $1 == "-n" && $2 == "default" ]]; then
  [[ ${AUDIO_METADATA_READ_FAIL:-0} == "0" ]] || exit 1
  cat <<'METADATA'
update: id:102 key:'target.object' value:'-1' type:'Spa:Id'
update: id:102 key:'target.node' value:'-1' type:'Spa:Id'
update: id:103 key:'target.object' value:'91' type:'Spa:Id'
update: id:106 key:'target.object' value:'85' type:'Spa:Id'
METADATA
else
  printf '<pw-metadata:%s>\n' "$*" >>"$AUDIO_CALLS_LOG"
fi
EOF
chmod +x "$tmp_dir/bin/pw-metadata"

export PATH="$tmp_dir/bin:$ROOT/bin:$PATH"
export AUDIO_SINK_INPUTS_FIXTURE="$tmp_dir/sink-inputs.json"
export AUDIO_SINKS_FIXTURE="$tmp_dir/sinks.json"
export AUDIO_CALLS_LOG="$tmp_dir/calls"
export AUDIO_DEFAULT_SINK=new-default

"$ROOT/bin/omarchy-audio-output-set-default" 91 new-default old-default
rg -Fx '<384>' "$AUDIO_CALLS_LOG" >/dev/null || fail "default output moves streams following the old default"
rg -Fx '<514>' "$AUDIO_CALLS_LOG" >/dev/null || fail "default output handles streams without PipeWire object metadata"
if rg -Fx '<512>' "$AUDIO_CALLS_LOG" >/dev/null; then
  fail "default output preserves explicit application routes"
fi
if rg -Fx '<513>' "$AUDIO_CALLS_LOG" >/dev/null; then
  fail "default output preserves an explicit route on the old default"
fi
if rg -Fx '<600>' "$AUDIO_CALLS_LOG" >/dev/null; then
  fail "default output leaves the EasyEffects processing stream in place"
fi
pass "default output preserves per-application routes"
: >"$AUDIO_CALLS_LOG"

AUDIO_METADATA_READ_FAIL=1 "$ROOT/bin/omarchy-audio-output-set-default" 91 new-default old-default
if rg -Fx '<move-sink-input>' "$AUDIO_CALLS_LOG" >/dev/null; then
  fail "default output moves streams when explicit-route metadata is unavailable"
fi
pass "default output fails safe when explicit routes cannot be read"
: >"$AUDIO_CALLS_LOG"

routes=$("$ROOT/bin/omarchy-audio-stream-routes")
[[ $(jq -r '.["384"].sink' <<<"$routes") == "85" ]] || fail "audio stream routes map an application serial to its sink serial"
[[ $(jq -r '.["384"].mode' <<<"$routes") == "default" ]] || fail "audio stream routes identify default-following applications"
[[ $(jq -r '.["512"].sink' <<<"$routes") == "91" ]] || fail "audio stream routes preserve multiple live routes"
[[ $(jq -r '.["512"].mode' <<<"$routes") == "override" ]] || fail "audio stream routes identify explicit application outputs"
"$ROOT/bin/omarchy-audio-stream-route-set" 384 85
rg -Fx '<move-sink-input>' "$AUDIO_CALLS_LOG" >/dev/null || fail "audio stream route setter calls pactl"
rg -Fx '<384>' "$AUDIO_CALLS_LOG" >/dev/null || fail "audio stream route setter preserves the stream serial"
rg -Fx '<85>' "$AUDIO_CALLS_LOG" >/dev/null || fail "audio stream route setter preserves the sink serial"
rg -Fx '<pw-metadata:-n default -- 102 target.object 85 Spa:Id>' "$AUDIO_CALLS_LOG" >/dev/null ||
  fail "pinning to the current sink writes its serial as an explicit target object"
rg -Fx '<pw-metadata:-n default -- 102 target.node 201 Spa:Id>' "$AUDIO_CALLS_LOG" >/dev/null ||
  fail "pinning to the current sink writes its object id as an explicit target node"
: >"$AUDIO_CALLS_LOG"
if AUDIO_MOVE_FAIL=1 "$ROOT/bin/omarchy-audio-stream-route-set" 384 91; then
  fail "audio stream route setter hides a failed move"
fi
: >"$AUDIO_CALLS_LOG"
"$ROOT/bin/omarchy-audio-stream-route-set" 384 85 default
rg -Fx '<pw-metadata:-n default -- 102 target.object -1 Spa:Id>' "$AUDIO_CALLS_LOG" >/dev/null ||
  fail "choosing the default output clears the explicit target object"
rg -Fx '<pw-metadata:-n default -- 102 target.node -1 Spa:Id>' "$AUDIO_CALLS_LOG" >/dev/null ||
  fail "choosing the default output clears the explicit target node"
if "$ROOT/bin/omarchy-audio-stream-route-set" spotify speakers >/dev/null 2>&1; then
  fail "audio stream route setter rejects non-serial identifiers"
fi
if AUDIO_METADATA_READ_FAIL=1 "$ROOT/bin/omarchy-audio-stream-routes" >/dev/null 2>&1; then
  fail "audio stream route reader treats missing target metadata as default-following"
fi
pass "audio stream routes are read, changed, and validated"
