#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const arrange = requireFromRoot('shell/plugins/display-arrange/Model.js')

// --- displays occupy logical space, not mode space ---

assertDeepEqual(
  arrange.logicalRect({ name: 'eDP-1', width: 2880, height: 1920, scale: 2, x: 0, y: 480 }),
  { name: 'eDP-1', x: 0, y: 480, width: 1440, height: 960 },
  'a display measures mode size divided by scale'
)
assertDeepEqual(
  arrange.logicalRect({ name: 'DP-1', width: 2560, height: 1440, scale: 1, x: 0, y: 0, transform: 1 }),
  { name: 'DP-1', x: 0, y: 0, width: 1440, height: 2560 },
  'a rotated display swaps width and height'
)
assertDeepEqual(
  arrange.logicalRect({ name: 'DP-1', width: 2560, height: 1440, scale: 0, x: 0, y: 0 }),
  { name: 'DP-1', x: 0, y: 0, width: 2560, height: 1440 },
  'a missing scale falls back to 1 rather than dividing by zero'
)

// --- mirroring is offered against live displays, not switched-off ones ---

assertEqual(arrange.isInternalName('eDP-1'), true, 'eDP is the built-in panel')
assertEqual(arrange.isInternalName('DP-7'), false, 'DP is an external display')
assertEqual(arrange.isInternalName(''), false, 'a nameless display is not the panel')

const bothLive = [{ name: 'eDP-1' }, { name: 'DP-7' }]
assertEqual(arrange.hasActiveDisplay(bothLive, true), true, 'the built-in panel is live')
assertEqual(arrange.hasActiveDisplay(bothLive, false), true, 'the external display is live')

// The regression: `hyprctl monitors all` still names a display the user
// switched off, so gating mirroring on it offered Mirror with nothing to
// mirror to, and pressing it re-enabled the panel that was deliberately off.
const panelOff = [{ name: 'DP-7' }]
assertEqual(arrange.hasActiveDisplay(panelOff, true), false, 'a switched-off panel is not live')
assertEqual(arrange.hasActiveDisplay(panelOff, false), true, 'the external display is still live')

const laptopOnly = [{ name: 'eDP-1' }]
assertEqual(arrange.hasActiveDisplay(laptopOnly, false), false, 'no external display to mirror to')

assertEqual(arrange.hasActiveDisplay([], true), false, 'no displays means nothing is live')
assertEqual(arrange.hasActiveDisplay(null, true), false, 'a missing listing is not live')

// --- the notification glyph is one character ---

// A "\\u" escape takes exactly four hex digits, so writing this glyph escaped
// yields U+F037 followed by a stray "9".
assertEqual([...arrange.displayGlyph].length, 1, 'the display glyph is a single character')
assertEqual(arrange.displayGlyph.codePointAt(0), 0xf0379, 'the display glyph is the one the panel uses')

// --- a layout that does not start at the origin ---

// The canvas draws a normalised layout, so a display left of 0x0 is drawn
// shifted even when the user never touched it. Comparing where displays
// actually are against where the canvas puts them is what catches that; against
// the normalised original it looks unchanged, and writing only the display the
// user dragged would leave the two covering different regions.
const offOrigin = [
  { name: 'eDP-1', x: -1440, y: 0, width: 1440, height: 900 },
  { name: 'DP-7', x: 0, y: 0, width: 2560, height: 1440 }
]
const dragged = [
  { name: 'eDP-1', x: -1440, y: 0, width: 1440, height: 900 },
  { name: 'DP-7', x: 0, y: 100, width: 2560, height: 1440 }
]
assertDeepEqual(
  arrange.changedPositions(arrange.normalized(offOrigin), arrange.normalized(dragged)),
  { 'DP-7': '1440x100' },
  'against the normalised original only the dragged display looks moved'
)
assertDeepEqual(
  arrange.changedPositions(offOrigin, arrange.normalized(dragged)),
  { 'eDP-1': '0x0', 'DP-7': '1440x100' },
  'against where they actually are, the shifted neighbour needs writing too'
)

// --- putting a layout back means where it was, not a tidied version ---

// Normalising is how a layout is drawn and how a new one is written. Reverting
// is neither: a layout that started off the origin has to come back off the
// origin, or the fail-safe meant to undo a change makes one of its own.
assertDeepEqual(
  arrange.positionsOf(offOrigin),
  { 'eDP-1': '-1440x0', 'DP-7': '0x0' },
  'a revert writes the positions the displays actually had'
)
assertDeepEqual(
  arrange.positionsOf(arrange.normalized(offOrigin)),
  { 'eDP-1': '0x0', 'DP-7': '1440x0' },
  'the normalised version of those positions is a different layout'
)

// --- the canvas fits the whole layout ---

const twoUp = [
  { name: 'eDP-1', x: 0, y: 480, width: 1440, height: 960 },
  { name: 'DP-7', x: 1440, y: 0, width: 2560, height: 1440 }
]
assertDeepEqual(
  arrange.bounds(twoUp),
  { x: 0, y: 0, width: 4000, height: 1440 },
  'bounds span every display'
)
assertEqual(arrange.fitScale(twoUp, 800, 400, 20), 760 / 4000, 'the layout fits the narrower axis')
assertEqual(arrange.fitScale([], 800, 400, 20), 1, 'an empty layout needs no scaling')

// --- overlap and contiguity, the two things a layout must get right ---

assertEqual(arrange.anyOverlap(twoUp), false, 'displays side by side do not overlap')
assertEqual(
  arrange.anyOverlap([
    { name: 'a', x: 0, y: 0, width: 100, height: 100 },
    { name: 'b', x: 50, y: 50, width: 100, height: 100 }
  ]),
  true,
  'displays sharing area overlap'
)
assertEqual(arrange.isContiguous(twoUp), true, 'touching displays are contiguous')
assertEqual(
  arrange.isContiguous([
    { name: 'a', x: 0, y: 0, width: 100, height: 100 },
    { name: 'b', x: 200, y: 0, width: 100, height: 100 }
  ]),
  false,
  'a gap between displays is a dead zone the pointer cannot cross'
)
assertEqual(
  arrange.isContiguous([
    { name: 'a', x: 0, y: 0, width: 100, height: 100 },
    { name: 'b', x: 100, y: 100, width: 100, height: 100 }
  ]),
  false,
  'displays meeting at a corner alone leave no width to cross'
)
assertEqual(
  arrange.isContiguous([{ name: 'a', x: 0, y: 0, width: 100, height: 100 }]),
  true,
  'a single display is trivially contiguous'
)

// --- snapping is what makes dragging usable ---

const anchor = [{ name: 'DP-7', x: 1440, y: 0, width: 2560, height: 1440 }]
assertDeepEqual(
  arrange.snap({ name: 'eDP-1', x: 1435, y: 3, width: 1440, height: 960 }, anchor, 40),
  { name: 'eDP-1', x: 1440, y: 0, width: 1440, height: 960 },
  'a near miss snaps flush to the neighbour'
)
assertDeepEqual(
  arrange.snap({ name: 'eDP-1', x: 10, y: 470, width: 1440, height: 960 }, anchor, 40),
  { name: 'eDP-1', x: 0, y: 480, width: 1440, height: 960 },
  'the left edge snaps against the neighbour and bottom edges align'
)
assertDeepEqual(
  arrange.snap({ name: 'eDP-1', x: 600, y: 600, width: 1440, height: 960 }, anchor, 40),
  { name: 'eDP-1', x: 600, y: 600, width: 1440, height: 960 },
  'a display far from its neighbours is left where it was dropped'
)

// --- a display dropped on another is pushed clear ---

assertDeepEqual(
  arrange.pushOut({ name: 'a', x: 100, y: 0, width: 200, height: 200 },
    [{ name: 'b', x: 0, y: 0, width: 200, height: 200 }]),
  { name: 'a', x: 200, y: 0, width: 200, height: 200 },
  'an overlapping display moves out the shortest way'
)
assertDeepEqual(
  arrange.pushOut({ name: 'a', x: 0, y: 150, width: 200, height: 200 },
    [{ name: 'b', x: 0, y: 0, width: 200, height: 200 }]),
  { name: 'a', x: 0, y: 200, width: 200, height: 200 },
  'a mostly-below overlap resolves downwards, not sideways'
)
assertDeepEqual(
  arrange.pushOut({ name: 'a', x: 500, y: 500, width: 200, height: 200 },
    [{ name: 'b', x: 0, y: 0, width: 200, height: 200 }]),
  { name: 'a', x: 500, y: 500, width: 200, height: 200 },
  'a display that overlaps nothing is left alone'
)
assertEqual(
  arrange.anyOverlap([
    { name: 'b', x: 0, y: 0, width: 200, height: 200 },
    arrange.pushOut({ name: 'a', x: 10, y: 10, width: 200, height: 200 },
      [{ name: 'b', x: 0, y: 0, width: 200, height: 200 }])
  ]),
  false,
  'the result of a push never overlaps'
)

// --- a display left floating is pulled onto its neighbour ---

const board = [{ name: 'b', x: 0, y: 0, width: 200, height: 200 }]

assertDeepEqual(
  arrange.attach({ name: 'a', x: 500, y: 0, width: 200, height: 200 }, board),
  { name: 'a', x: 200, y: 0, width: 200, height: 200 },
  'a display floating to the right is pulled against the right edge'
)
assertDeepEqual(
  arrange.attach({ name: 'a', x: 0, y: 600, width: 200, height: 200 }, board),
  { name: 'a', x: 0, y: 200, width: 200, height: 200 },
  'a display floating below is pulled against the bottom edge'
)
assertDeepEqual(
  arrange.attach({ name: 'a', x: 200, y: 0, width: 200, height: 200 }, board),
  { name: 'a', x: 200, y: 0, width: 200, height: 200 },
  'a display already touching is left where it is'
)

// Diagonally away, so it would meet at a corner without the clamp — which is
// as uncrossable as a gap.
const cornered = arrange.attach({ name: 'a', x: 600, y: 600, width: 200, height: 200 }, board)
assertEqual(arrange.isContiguous(board.concat([cornered])), true, 'a diagonal drop still shares a real edge')
assertEqual(arrange.anyOverlap(board.concat([cornered])), false, 'attaching never overlaps')

// --- rotation re-measures the display, it does not just relabel it ---

assertDeepEqual(
  arrange.rotated({ name: 'a', x: 10, y: 20, width: 2560, height: 1440 }, 0, 1),
  { name: 'a', x: 10, y: 20, width: 1440, height: 2560 },
  'rotating to 90 degrees swaps the edges the layout sees'
)
assertDeepEqual(
  arrange.rotated({ name: 'a', x: 0, y: 0, width: 1440, height: 2560 }, 1, 3),
  { name: 'a', x: 0, y: 0, width: 1440, height: 2560 },
  '90 to 270 keeps the same edges, both being quarter turns'
)
assertDeepEqual(
  arrange.rotated({ name: 'a', x: 0, y: 0, width: 2560, height: 1440 }, 0, 2),
  { name: 'a', x: 0, y: 0, width: 2560, height: 1440 },
  '180 degrees leaves the edges alone'
)
assertEqual(arrange.nextTransform(0), 1, 'rotation steps through the quarter turns')
assertEqual(arrange.nextTransform(3), 0, 'rotation wraps back to upright')
assertEqual(arrange.transformLabel(3), '270°', 'each rotation has a readable label')

// --- normalising keeps the numbers readable across repeated edits ---

assertDeepEqual(
  arrange.normalized([
    { name: 'a', x: -1440, y: -480, width: 1440, height: 960 },
    { name: 'b', x: 0, y: 0, width: 2560, height: 1440 }
  ]),
  [
    { name: 'a', x: 0, y: 0, width: 1440, height: 960 },
    { name: 'b', x: 1440, y: 480, width: 2560, height: 1440 }
  ],
  'a layout is shifted so its top-left sits at the origin'
)

// --- only what moved gets written ---

assertDeepEqual(
  arrange.changedPositions(twoUp, [
    { name: 'eDP-1', x: 0, y: 0, width: 1440, height: 960 },
    { name: 'DP-7', x: 1440, y: 0, width: 2560, height: 1440 }
  ]),
  { 'eDP-1': '0x0' },
  'only displays that moved are written back'
)
assertDeepEqual(
  arrange.changedPositions(twoUp, twoUp),
  {},
  'an unchanged layout writes nothing'
)
JS
