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

players[0].canControl = true
players[0].volumeSupported = true
players[0].volume = 0.39
streams[1].audio = { volume: 0.8 }

assertEqual(audio.mprisPlayerForStream(streams[1], players, streams), players[0], 'audio finds the MPRIS player for a stream')
const qmlPlayerList = { 0: players[0], length: 1 }
assertEqual(audio.mprisPlayerForStream(streams[1], qmlPlayerList, streams), players[0], 'audio reads Quickshell array-like player lists')
assertEqual(audio.streamLabel(streams[1], qmlPlayerList, streams), 'Spotify', 'audio labels generic streams from array-like player lists')
assertEqual(audio.streamVolume(streams[1], players[0]), 0.39, 'audio reads persistent player volume when available')
assertEqual(audio.setStreamVolume(streams[1], players[0], 0.65), 0.65, 'audio returns the updated stream volume')
assertEqual(players[0].volume, 0.65, 'audio updates persistent player volume')
assertEqual(streams[1].audio.volume, 0.65, 'audio updates live stream volume')

const unsupportedPlayer = { canControl: true, volumeSupported: false, volume: 0.2 }
assertEqual(audio.streamVolume(streams[1], unsupportedPlayer), 0.65, 'audio falls back to live stream volume')
audio.setStreamVolume(streams[1], unsupportedPlayer, 0.5)
assertEqual(unsupportedPlayer.volume, 0.2, 'audio leaves unsupported player volume unchanged')
assertEqual(streams[1].audio.volume, 0.5, 'audio still updates streams without player volume support')
JS
