#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const osd = requireFromRoot('shell/plugins/osd/OsdModel.js')
const range = requireFromRoot('shell/Ui/RangeModel.js')

assertEqual(osd.iconFor('', 0), osd.iconFor('muted', 50), 'osd falls back to muted icon at zero percent')
assertEqual(osd.iconFor('volume-high', 1), osd.iconFor('', 100), 'osd maps high volume aliases')
assertEqual(osd.iconFor('logout', 50), '󰍃', 'osd maps logout icon')
assertEqual(osd.iconFor('custom-symbol', 50), 'custom-symbol', 'osd preserves unknown explicit icons')
assertEqual(osd.widestIcon, osd.iconFor('volume-high', 100), 'osd sizes the icon column to a glyph it can show')

assert(!range.thresholdEnabled(0, 100, 100), 'a 100 percent maximum keeps threshold styling disabled')
assert(range.thresholdEnabled(0, 101, 100), 'a maximum just above 100 enables threshold styling')
assertEqual(range.fraction(0, 0, 150), 0, 'zero volume starts at the beginning of the range')
assertEqual(range.fraction(100, 0, 125), 0.8, 'the threshold follows a non-150 maximum')
assertEqual(range.fraction(100, 0, 150), 100 / 150, 'the threshold is two thirds only for a 150 maximum')
assertEqual(range.fraction(100, 0, 200), 0.5, 'the threshold fraction is derived from the maximum')
assert(!range.amplified(100, 0, 150, 100), '100 percent is not amplified')
assert(range.amplified(101, 0, 150, 100), 'a value above 100 percent is amplified')
assert(range.amplified(150, 0, 150, 100), 'the configured maximum can be amplified')

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
  osd.stateForShow('volume', '', '125', '150', '125%', '800'),
  {
    iconKey: 'volume',
    maxValue: 150,
    hasProgress: true,
    value: 125,
    message: '125%',
    icon: osd.iconFor('volume', 83),
    duration: 800
  },
  'osd preserves actual amplified volume text while scaling progress to its maximum'
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
