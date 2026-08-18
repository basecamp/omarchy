#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test "tray model helpers" <<'JS'
const tray = requireFromRoot('shell/plugins/bar/widgets/TrayModel.js')

assert(tray.itemNamed({ id: 'dropbox-client' }, 'dropbox'), 'tray matches item ids')

// Recolor decisions are made from an icon's pixels, not its name. samplePixels
// walks a flat RGBA array exactly as Canvas getImageData().data hands it over,
// and owns the thresholds: referencing them from QML instead read undefined,
// which made every comparison false and every icon look like a silhouette.
const rgba = (n, r, g, b, a = 255) => {
  const out = []
  for (let i = 0; i < n; i++) out.push(r, g, b, a)
  return out
}
const barLum = tray.relativeLuminance(0x2e / 255, 0x34 / 255, 0x40 / 255)
const lumOf = (v) => tray.relativeLuminance(v / 255, v / 255, v / 255)

const flatDark = tray.samplePixels(rgba(100, 0x33, 0x33, 0x33))
assert(flatDark.opaque === 100, 'samplePixels counts every opaque pixel')
assert(flatDark.colored === 0, 'a flat grey fill has no colored pixels')

const teamsPurple = tray.samplePixels(rgba(100, 75, 83, 188))
assert(teamsPurple.colored === 100, 'a saturated fill is all colored pixels')

assert(tray.samplePixels(rgba(100, 0x33, 0x33, 0x33, 10)).opaque === 0,
  'samplePixels ignores near-transparent pixels')
assert(tray.samplePixels([]).opaque === 0, 'an empty buffer yields no pixels')

// A buffer that is not a whole number of pixels must not contribute a partial
// one: reading past the end gives undefined channels, and undefined <= the alpha
// floor is false, so the fragment would count as opaque and poison the average.
assert(tray.samplePixels(rgba(2, 0x33, 0x33, 0x33).slice(0, 5)).opaque === 1,
  'a trailing partial pixel is ignored')
assert(!Number.isNaN(tray.samplePixels(rgba(2, 0x33, 0x33, 0x33).slice(0, 6)).luminance),
  'a truncated buffer does not produce NaN luminance')

assert(tray.sampleIsSilhouette(flatDark), 'a flat grey sample is a silhouette')
assert(!tray.sampleIsSilhouette(teamsPurple), 'a saturated sample is not a silhouette')
assert(!tray.sampleIsSilhouette(tray.samplePixels([])), 'an empty sample is not a silhouette')

assert(tray.sampleNeedsRecolor(flatDark, barLum),
  'tray recolors a dark silhouette that cannot be read on the bar')
assert(!tray.sampleNeedsRecolor(teamsPurple, barLum),
  'tray leaves a full-color icon its own colors')
assert(!tray.sampleNeedsRecolor(tray.samplePixels(rgba(100, 0xde, 0xde, 0xde)), barLum),
  'tray leaves a light silhouette alone, it already contrasts')
assert(!tray.sampleNeedsRecolor(flatDark, lumOf(0xf5)),
  'the same dark silhouette is left alone on a light bar')

assert(Math.abs(tray.contrastRatio(1, 0) - 21) < 0.001, 'contrast of white on black is 21:1')
assert(Math.abs(tray.contrastRatio(0.5, 0.5) - 1) < 0.001, 'contrast of a color with itself is 1:1')
assert(tray.itemNamed({ title: 'Dropbox' }, 'dropbox'), 'tray matches item titles')
assert(tray.itemNamed({ tooltipTitle: 'LocalSend' }, 'localsend'), 'tray matches item tooltips')
assert(!tray.itemNamed({ id: 'nextcloud' }, 'dropbox'), 'tray ignores items named for something else')

const layout = {
  left: [{ id: 'omarchy.menu' }],
  center: [],
  right: [{ id: 'omarchy.dropbox' }, { id: 'omarchy.tray' }]
}

assert(tray.layoutHasWidget(layout, 'omarchy.dropbox'), 'tray finds dedicated dropbox widget in layout')
assert(tray.ownedByOmarchy({ id: 'dropbox' }, layout), 'tray suppresses dropbox when dedicated widget is in bar')
assert(!tray.ownedByOmarchy({ id: 'dropbox' }, { left: [], center: [], right: [] }), 'tray keeps dropbox when dedicated widget is absent')
assert(tray.ownedByOmarchy({ id: 'qlBCprNUqU', title: 'localsend' }, { left: [], center: [], right: [] }), 'tray suppresses localsend regardless of layout')
assert(!tray.ownedByOmarchy({ id: 'nextcloud' }, layout), 'tray keeps unrelated tray items')
JS
