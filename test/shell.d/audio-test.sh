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

assertDeepEqual(
  audio.routeCommand(64, 'alsa_output.analog-stereo'),
  ['pw-metadata', '-n', 'default', '64', 'target.object', 'alsa_output.analog-stereo'],
  'audio pins a stream to an output'
)
assertDeepEqual(
  audio.routeCommand(64, audio.DEFAULT_ROUTE),
  ['pw-metadata', '-n', 'default', '64', 'target.object', '-1'],
  'audio hands a stream back to the default output'
)
const routeMetadata = [
  "update: id:120 key:'target.object' value:'sink.a' type:'(null)'",
  "update: id:121 key:'target.object' value:'-1' type:'(null)'",
  "update: id:122 key:'volume' value:'0.5' type:'(null)'"
].join('\n')
const routeTargets = audio.parseRouteTargets(routeMetadata)

assertDeepEqual(routeTargets, { '120': 'sink.a', '121': '-1' }, 'audio reads routing out of the default metadata object')
assertDeepEqual(audio.parseRouteTargets(''), {}, 'audio handles empty metadata')
assertEqual(audio.routeTargetOf({ id: 120 }, routeTargets), 'sink.a', 'audio reads a pinned stream')
assertEqual(audio.routeTargetOf({ id: 121 }, routeTargets), audio.DEFAULT_ROUTE, 'audio reads a cleared pin as following the default')
assertEqual(audio.routeTargetOf({ id: 999 }, routeTargets), audio.DEFAULT_ROUTE, 'audio reads an unlisted stream as following the default')
assert(audio.routeIsPinned({ id: 120 }, routeTargets), 'audio reports a pinned stream')
assert(!audio.routeIsPinned({ id: 999 }, routeTargets), 'audio reports an unpinned stream')

const routeSinks = [
  { ready: true, name: 'sink.a', nickname: 'Speakers' },
  { ready: true, name: 'sink.b', nickname: 'HDMI' }
]
assertDeepEqual(audio.routeOptions(routeSinks), [audio.DEFAULT_ROUTE, 'sink.a', 'sink.b'], 'audio offers the default output first')
assertEqual(audio.nextRouteTarget(audio.routeOptions(routeSinks), audio.DEFAULT_ROUTE), 'sink.a', 'audio cycles from the default to the first output')
assertEqual(audio.nextRouteTarget(audio.routeOptions(routeSinks), 'sink.b'), audio.DEFAULT_ROUTE, 'audio cycles from the last output back to the default')
assertEqual(audio.routeLabel({ id: 999 }, routeSinks, null, routeTargets), 'Follow default output', 'audio labels an unpinned stream')
assertEqual(audio.routeLabel({ id: 120 }, routeSinks, null, routeTargets), 'Speakers', 'audio labels a pinned stream by device')
assertEqual(audio.routeLabel({ id: 999 }, routeSinks, routeSinks[1], routeTargets), 'HDMI', 'audio prefers the linked output over the pin')
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
