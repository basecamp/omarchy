#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const osd = requireFromRoot('shell/plugins/osd/OsdModel.js')

assertEqual(osd.iconFor('', 0), osd.iconFor('muted', 50), 'osd falls back to muted icon at zero percent')
assertEqual(osd.iconFor('volume-high', 1), osd.iconFor('', 100), 'osd maps high volume aliases')

// Each volume level needs a distinct glyph. These are the Material Design
// speakers, matching every other icon in iconFor(). The MDI names do not
// describe wave counts: volume_low draws a bare speaker, volume_medium one
// wave, volume_high two, and volume_off a slashed speaker.
assertEqual(osd.iconFor('volume-low', 20), '󰕿', 'osd shows the low volume speaker')
assertEqual(osd.iconFor('volume-medium', 50), '󰖀', 'osd shows the medium volume speaker')
assertEqual(osd.iconFor('volume-high', 80), '󰕾', 'osd shows the high volume speaker')
assertEqual(osd.iconFor('volume-muted', 20), '󰖁', 'osd shows the slashed speaker when muted')

// The audio panel's bar scroll sends no icon at all, so the percentage
// fallback must land on the same speakers as the named levels.
assertEqual(osd.iconFor('', 20), osd.iconFor('volume-low', 20), 'osd fallback matches low')
assertEqual(osd.iconFor('', 50), osd.iconFor('volume-medium', 50), 'osd fallback matches medium')
assertEqual(osd.iconFor('', 80), osd.iconFor('volume-high', 80), 'osd fallback matches high')
assertEqual(osd.iconFor('logout', 50), '󰍃', 'osd maps logout icon')
assertEqual(osd.iconFor('custom-symbol', 50), 'custom-symbol', 'osd preserves unknown explicit icons')
assertEqual(osd.widestIcon, osd.iconFor('volume-high', 100), 'osd sizes the icon column to a glyph it can show')

assertDeepEqual(
  osd.stateForShow('volume', '', '75', '100', '', '800'),
  {
    iconKey: 'volume',
    maxValue: 100,
    hasProgress: true,
    value: 75,
    message: '75%',
    icon: osd.iconFor('volume', 75),
    duration: 800
  },
  'osd builds progress state'
)

assertDeepEqual(
  osd.stateForShow('media-pause', 'Paused', '', '100', '', 'nope'),
  {
    iconKey: 'media-pause',
    maxValue: 100,
    hasProgress: false,
    value: 0,
    message: 'Paused',
    icon: osd.iconFor('media-pause', -1),
    duration: 1200
  },
  'osd builds message state'
)
JS
