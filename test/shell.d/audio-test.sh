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
assertEqual(audio.parseOutputTargets('not json'), null, 'audio rejects malformed output target JSON')
assertDeepEqual(audio.parseOutputTargets('[]'), [], 'audio accepts an empty output target snapshot')
assertEqual(audio.parseOutputTargets('[{"portName":"missing-sink"}]'), null, 'audio rejects snapshots containing no valid targets')

const parsedTargets = audio.parseOutputTargets(JSON.stringify([
  { sinkName: 'analog', portName: 'lineout', portDescription: 'Line Out', sinkDescription: 'Built-in Audio Analog Stereo', kind: 'speaker', active: true },
  { sinkName: 'analog', portName: 'headphones', portDescription: 'Headphones', sinkDescription: 'Built-in Audio Analog Stereo', kind: 'headphones', active: false },
  { sinkName: 'analog', portName: 'headphones', portDescription: 'Duplicate' },
  { portName: 'missing-sink' },
  null
]))
assertEqual(parsedTargets.length, 2, 'audio validates and deduplicates output targets')

const analogSink = { id: 42, name: 'analog', description: 'Analog Stereo' }
const joinedTargets = audio.joinOutputTargets(parsedTargets, [analogSink])
assertEqual(joinedTargets.length, 2, 'audio joins output targets to live sinks')
assertEqual(joinedTargets[0].label, 'Line Out', 'audio labels a multi-port line-out target')
assertEqual(joinedTargets[1].label, 'Headphones', 'audio labels a headphone target')
assert(joinedTargets[0].active && !joinedTargets[1].active, 'audio keeps port-specific active state')

const fallbackTargets = audio.fallbackOutputTargets([analogSink], analogSink)
assertEqual(fallbackTargets.length, 1, 'audio builds a sink-only fallback target')
assert(fallbackTargets[0].active, 'audio marks the default fallback sink active')
assert(audio.outputTargetGlyph(joinedTargets[1]).length > 0, 'audio maps output target glyphs')
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
