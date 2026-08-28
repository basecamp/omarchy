#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const media = requireFromRoot('shell/plugins/services/media/MediaModel.js')

assert(media.isProxyPlayer({ dbusName: 'org.mpris.MediaPlayer2.playerctld' }), 'media detects playerctld proxy by DBus name')
assert(media.isProxyPlayer({ desktopEntry: 'playerctld' }), 'media detects playerctld proxy by desktop entry')
assert(media.hasMetadata({ identity: 'Spotify' }), 'media detects identity metadata')
assert(media.hasTrackMetadata({ trackTitle: 'Track' }), 'media detects track metadata')
assert(media.playerCanControl({ canGoNext: true }), 'media detects controllable players')
assert(media.canHandleAction({ canTogglePlaying: true }, 'playPause'), 'media maps playPause capability')
assert(media.canCycleSource({ identity: 'Spotify', canPlay: true }), 'media detects cycleable sources')

assert(media.isPlaybackStream({ isStream: true, type: 'Stream/Output/Audio' }), 'media detects playback streams')
assertEqual(media.streamLabelKey('PipeWire ALSA [Chromium]'), 'chromium', 'media normalizes stream labels')
assertEqual(
  media.rawStreamLabel({ ready: true, properties: { 'application.name': 'Chromium' }, name: 'fallback' }),
  'Chromium',
  'media extracts raw stream labels'
)
assertEqual(
  media.playerAppLabel({ dbusName: 'org.mpris.MediaPlayer2.spotify.instance42' }),
  'spotify',
  'media derives player app labels from DBus names'
)
assert(media.playerHasPlaybackStream(
  { desktopEntry: 'chromium' },
  [{ ready: true, properties: { 'application.name': 'Chromium' } }]
), 'media matches players to playback streams')

assertEqual(media.playerKey({ dbusName: 'org.mpris.MediaPlayer2.spotify' }), 'org.mpris.MediaPlayer2.spotify', 'media derives stable player keys')
const track = { trackTitle: 'Song', trackArtist: 'Artist', trackAlbum: 'Album', trackArtUrl: 'file:///cover.jpg' }
const trackSignature = media.trackSignature(track)
assert(!media.trackChanged(trackSignature, { ...track }), 'media detects unchanged track metadata')
assert(media.trackChanged(trackSignature, { ...track, trackTitle: 'Next song' }), 'media detects changed track metadata')
assertEqual(media.labelFor({ trackTitle: 'Song', identity: 'Spotify' }), 'Song', 'media labels players by track first')
assertEqual(media.osdMessage({ trackTitle: 'Song', trackArtist: 'Artist' }, 'Fallback'), 'Song - Artist', 'media builds OSD messages')
assertEqual(media.osdMessage(null, 'Fallback'), 'Fallback', 'media falls back OSD messages')
// ---- bar widget settings
// Comments stripped: a wiring assertion that a commented-out line can satisfy
// passes while the widget is broken.
const widgetSource = fs.readFileSync(root + '/shell/plugins/services/media/BarWidget.qml', 'utf8')
  .replace(/^\s*\/\/.*$/gm, '')

assert(/setting\("scroll",\s*true\)/.test(widgetSource), 'media widget reads scroll, defaulting to the previous scrolling behaviour')
assert(/setting\("separator",\s*"  ·  "\)/.test(widgetSource), 'media widget reads separator, defaulting to the previous string')
assert(/setting\("iconGap",\s*6\)/.test(widgetSource), 'media widget reads iconGap, defaulting to the previous spacing')
assert(/setting\("maxLabelWidth",\s*180\)/.test(widgetSource), 'media widget reads maxLabelWidth, defaulting to the previous cap')

assert(/spacing:\s*Style\.space\(root\.iconGap\)/.test(widgetSource), 'media widget spaces the control from the label by iconGap')
assert(/text:\s*root\.title \+ \(root\.artist \? root\.separator \+ root\.artist : ""\)/.test(widgetSource), 'media widget joins title and artist with the configured separator')

// Both branches must be gated, or the two label layouts render on top of each other.
assert(/id: labelText[\s\S]{0,200}?visible: root\.scrollLabel\b/.test(widgetSource), 'media widget shows the scrolling label only when scrolling')
assert(/id: staticLabel[\s\S]{0,200}?visible: !root\.scrollLabel\b/.test(widgetSource), 'media widget shows the static label only when not scrolling')
assert(/running: root\.scrollLabel &&/.test(widgetSource), 'media widget runs the scroll animation only when scrolling')

// The separator has to come out of the budget, otherwise a long title plus a
// long artist renders at maxLabelWidth + separator width.
assert(/readonly property real separatorWidth: root\.artist !== "" \? sepText\.implicitWidth : 0/.test(widgetSource), 'media widget measures the separator for the static budget')
assert(/artistWidth: Math\.min\(root\.maxLabelWidth \* 0\.35, artistText\.implicitWidth\)/.test(widgetSource), 'media widget caps the static artist at its share')
assert(/titleWidth: Math\.min\(\s*Math\.max\(0, root\.maxLabelWidth - separatorWidth - artistWidth\), titleText\.implicitWidth\)/.test(widgetSource), 'media widget gives the static title the budget left after separator and artist')

assert(/id: titleText[\s\S]{0,220}?elide: Text\.ElideRight/.test(widgetSource), 'media widget elides the static title independently')
assert(/id: artistText[\s\S]{0,220}?elide: Text\.ElideRight/.test(widgetSource), 'media widget elides the static artist independently')
JS
