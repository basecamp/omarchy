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

const mediaPlayer = {
  trackTitle: 'Moonshot',
  trackArtist: 'The Murder Capital',
  isPlaying: true,
  canGoPrevious: true,
  canTogglePlaying: true,
  canGoNext: true
}
assert(audio.mediaVisible(mediaPlayer), 'audio shows media with live metadata')
assert(audio.mediaVisible({ trackTitle: 'Title only', isPlaying: false }), 'audio shows title-only paused media')
assert(audio.mediaVisible({ trackArtist: 'Artist only', isPlaying: false }), 'audio shows artist-only paused media')
assert(audio.mediaVisible({ isPlaying: false }, '', '', false) === false, 'audio hides blank media without cache')
assert(audio.mediaVisible(null, 'Moonshot', 'The Murder Capital', true), 'audio keeps cached media during null-player gap')
assert(audio.mediaVisible(null, 'Moonshot', 'The Murder Capital', false) === false, 'audio clears cached media after gap timeout')
assert(audio.mediaVisible({ isPlaying: false }, 'Moonshot', '', true), 'audio keeps cached media while replacement metadata is blank')
assertEqual(audio.firstEnabledMediaControl(mediaPlayer), 1, 'audio enters media controls on play/pause')
assertDeepEqual(audio.mediaActionNames(), ['previous', 'playPause', 'next'], 'audio uses canonical media action order')
const actionNames = audio.mediaActionNames()
actionNames.reverse()
assertDeepEqual(audio.mediaActionNames(), ['previous', 'playPause', 'next'], 'audio returns a copy of canonical media actions')
assertEqual(audio.firstEnabledMediaControl({ canGoPrevious: true }), 0, 'audio falls back to previous control')
assertEqual(audio.firstEnabledMediaControl({ canGoNext: true }), 2, 'audio falls back to next control')
assertEqual(audio.mediaActions({ canGoPrevious: true, canGoNext: true }).map(control => control.enabled).join(','), 'true,false,true', 'audio disables unsupported controls independently')
assertEqual(audio.nextEnabledMediaControl({ canGoPrevious: true, canGoNext: true }, 0, 1), 2, 'audio skips unsupported controls')
assertEqual(audio.nextEnabledMediaControl({ canGoPrevious: true, canGoNext: true }, 2, 1), 2, 'audio clamps at the next control')
assertEqual(audio.nextEnabledMediaControl({ canGoPrevious: true, canGoNext: true }, 0, -1), 0, 'audio clamps at the previous control')
assertEqual(audio.nextEnabledMediaControl({}, 1, 1), 1, 'audio safely keeps focus when no controls are enabled')
JS
