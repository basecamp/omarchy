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
const outputProfiles = audio.parseOutputProfiles(JSON.stringify([
  { cardName: 'alsa_card.gpu', profileName: 'output:hdmi-stereo-extra1', label: 'Right Monitor', description: 'Digital Stereo (HDMI 2) Output' }
]))
assertEqual(outputProfiles[0].label, 'Right Monitor', 'audio parses inactive output profile labels')
assertEqual(outputProfiles[0].description, 'Digital Stereo (HDMI 2)', 'audio cleans inactive output profile descriptions')
assertDeepEqual(audio.parseOutputProfiles('{bad json'), [], 'audio rejects malformed output profile data')
assertEqual(
  audio.outputProfileSinkName('alsa_card.pci-0000_29_00.1', 'output:hdmi-stereo-extra1'),
  'alsa_output.pci-0000_29_00.1.hdmi-stereo-extra1',
  'audio derives the sink name created by an ALSA output profile'
)

const activeSink = {
  name: 'alsa_output.gpu.hdmi-stereo',
  ready: false
}
const outputRows = audio.outputRows([activeSink], [
  { cardName: 'alsa_card.gpu', profileName: 'output:hdmi-stereo', label: 'Left Monitor', description: 'Digital Stereo' },
  { cardName: 'alsa_card.gpu', profileName: 'output:hdmi-stereo-extra1', label: 'Right Monitor', description: 'Digital Stereo' }
])
assertEqual(outputRows.length, 2, 'audio combines active sinks with inactive card profiles')
assertEqual(outputRows[0].kind, 'sink', 'audio keeps active sinks as selectable output rows')
assertEqual(outputRows[0].label, 'Left Monitor', 'audio labels active sinks from their card ports')
assertEqual(outputRows[1].kind, 'profile', 'audio exposes inactive profiles as selectable output rows')
assertEqual(outputRows[1].label, 'Right Monitor', 'audio keeps monitor names on profile rows')

const reorderedRows = audio.outputRows([{ ...activeSink, name: 'alsa_output.gpu.hdmi-stereo-extra1' }], [
  { cardName: 'alsa_card.gpu', profileName: 'output:hdmi-stereo', label: 'Left Monitor', description: 'Digital Stereo' },
  { cardName: 'alsa_card.gpu', profileName: 'output:hdmi-stereo-extra1', label: 'Right Monitor', description: 'Digital Stereo' }
])
assertEqual(reorderedRows[0].label, 'Left Monitor', 'audio keeps output rows sorted when the active profile changes')
assertEqual(reorderedRows[1].label, 'Right Monitor', 'audio does not move the selected output to the front')
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
