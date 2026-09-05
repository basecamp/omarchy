#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Static contract: Panel.qml must collapse duplicate PipeWire nodes before
# feeding the sound menu Repeaters (issue #9887).
panel="$ROOT/shell/plugins/panels/audio/Panel.qml"
model="$ROOT/shell/plugins/panels/audio/Model.js"

[[ -f $panel ]] || fail "audio Panel.qml exists"
[[ -f $model ]] || fail "audio Model.js exists"

grep -q 'dedupeAudioNodes' "$panel" || fail "Panel.qml calls dedupeAudioNodes"
grep -q 'function dedupeAudioNodes' "$model" || fail "Model.js defines dedupeAudioNodes"
grep -q 'rawAudioSinks' "$panel" || fail "Panel.qml still builds rawAudioSinks"
grep -q 'rawAudioSources' "$panel" || fail "Panel.qml still builds rawAudioSources"
grep -q 'isMonitorSource' "$panel" || fail "Panel.qml filters monitor sources"
grep -q 'function isMonitorSource' "$model" || fail "Model.js defines isMonitorSource"

# rawAudioSinks/Sources must run through dedupe rather than identity indexOf.
awk '
  /readonly property var rawAudioSinks:/ { in_sinks = 1 }
  in_sinks && /return dedupeAudioNodes\(list\)/ { sinks_deduped = 1 }
  in_sinks && /^  readonly property var / && !/rawAudioSinks:/ { in_sinks = 0 }
  /readonly property var rawAudioSources:/ { in_sources = 1 }
  in_sources && /return dedupeAudioNodes\(list\)/ { sources_deduped = 1 }
  in_sources && /^  readonly property var / && !/rawAudioSources:/ { in_sources = 0 }
  END {
    if (!sinks_deduped) { print "rawAudioSinks missing dedupeAudioNodes return" > "/dev/stderr"; exit 1 }
    if (!sources_deduped) { print "rawAudioSources missing dedupeAudioNodes return" > "/dev/stderr"; exit 1 }
  }
' "$panel" || fail "rawAudio lists return dedupeAudioNodes(list)"
pass "Panel.qml dedupes rawAudioSinks and rawAudioSources"

run_node_test <<'JS'
const audio = requireFromRoot('shell/plugins/panels/audio/Model.js')

function node(partial) {
  return Object.assign({ ready: true, properties: {} }, partial)
}

// Same PipeWire name twice (default handle + catalog entry).
const sameName = audio.dedupeAudioNodes([
  node({ name: 'alsa_output.pci-speakers', description: 'Built-in Audio Speakers Output' }),
  node({ name: 'alsa_output.pci-speakers', description: 'Built-in Audio Speakers Output', id: 99 })
])
assertEqual(sameName.length, 1, 'dedupe collapses identical node.name')
assertEqual(sameName[0].name, 'alsa_output.pci-speakers', 'dedupe keeps first node.name match')

// Distinct names, identical friendly label (ALSA vs pulse path to same hardware).
const sameLabel = audio.dedupeAudioNodes([
  node({
    name: 'alsa_output.pci-0000_00_1f.3.analog-stereo',
    properties: { 'node.nick': 'Speakers' }
  }),
  node({
    name: 'alsa_output.pci-0000_00_1f.3.HiFi__hw_sofhdadsp_0__sink',
    properties: { 'node.nick': 'Built-in Audio Speakers Output' }
  })
])
assertEqual(sameLabel.length, 1, 'dedupe collapses matching friendlyDeviceLabel')
assertEqual(audio.nodeLabel(sameLabel[0]), 'Speakers', 'dedupe keeps first friendly label')

// Truly distinct devices stay listed.
const distinct = audio.dedupeAudioNodes([
  node({ name: 'alsa_output.pci-speakers', properties: { 'node.nick': 'Speakers' } }),
  node({ name: 'bluez_output.airpods', properties: { 'device.product.name': 'AirPods Headphones' } }),
  node({ name: 'alsa_output.pci-hdmi', properties: { 'node.nick': 'HDMI' } })
])
assertEqual(distinct.length, 3, 'dedupe keeps distinct sinks')

// Default-first ordering: preferred node wins when a later candidate matches.
const preferred = node({ name: 'preferred_sink', properties: { 'node.nick': 'Speakers' }, id: 1 })
const duplicate = node({ name: 'other_path_sink', properties: { 'node.nick': 'Speakers' }, id: 2 })
const ordered = audio.dedupeAudioNodes([preferred, duplicate])
assertEqual(ordered.length, 1, 'dedupe prefers earlier (default) entry')
assertEqual(ordered[0].id, 1, 'dedupe keeps default sink object')

// Sources: same microphone under two node paths.
const mics = audio.dedupeAudioNodes([
  node({ name: 'alsa_input.pci-analog', properties: { 'node.nick': 'Built-in Audio Microphones Input' } }),
  node({ name: 'alsa_input.pci-hifi', description: 'Built-in Audio Microphones Input' })
])
assertEqual(mics.length, 1, 'dedupe collapses duplicate input labels')
assertEqual(audio.nodeLabel(mics[0]), 'Microphone', 'dedupe keeps friendly mic label')

assert(audio.isMonitorSource(node({ name: 'alsa_output.pci-speakers.monitor' })), 'monitor suffix detected')
assert(audio.isMonitorSource(node({ name: 'virtual', type: 'Stream/Input/Audio/Monitor' })), 'monitor media class detected')
assert(!audio.isMonitorSource(node({ name: 'alsa_input.pci-mic', description: 'Microphone' })), 'real mic is not a monitor')

// Empty / sparse inputs are safe.
assertDeepEqual(audio.dedupeAudioNodes([]), [], 'dedupe handles empty list')
assertDeepEqual(audio.dedupeAudioNodes([null, undefined]), [], 'dedupe skips nullish entries')
assertEqual(audio.dedupeAudioNodes([node({ name: 'only' })]).length, 1, 'dedupe keeps singleton')
JS
