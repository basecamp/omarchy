#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const refresh = requireFromRoot('shell/plugins/services/refresh-rate/RefreshRateModel.js')

const panel = {
  name: 'eDP-1', width: 2560, height: 1600, refreshRate: 60.008,
  scale: 1.6, x: 0, y: 0,
  availableModes: ['2560x1600@60.01Hz', '2560x1600@165.02Hz', '1920x1080@120.00Hz']
}
const external = {
  name: 'HDMI-A-1', width: 2560, height: 1440, refreshRate: 59.951,
  scale: 1, x: 1600, y: 0,
  availableModes: ['2560x1440@59.95Hz', '2560x1440@143.91Hz']
}

assertEqual(refresh.isInternal('eDP-1'), true, 'refresh rate treats eDP as internal')
assertEqual(refresh.isInternal('LVDS-1'), true, 'refresh rate treats LVDS as internal')
assertEqual(refresh.isInternal('DSI-1'), true, 'refresh rate treats DSI as internal')
assertEqual(refresh.isInternal('HDMI-A-1'), false, 'refresh rate treats HDMI as external')
assertEqual(refresh.isInternal(''), false, 'refresh rate rejects a missing output name')

// Only the modes at the resolution already in use, so a rate change can never
// also change the resolution.
assertEqual(
  refresh.ratesFor(panel).join(','), '60.01,165.02',
  'refresh rate offers only the rates at the current resolution'
)
assertEqual(refresh.ratesFor(null).length, 0, 'refresh rate handles a missing monitor')

assertEqual(refresh.targetRate(panel, false, 60, 50), '165.02', 'refresh rate runs fast on mains above the threshold')
assertEqual(refresh.targetRate(panel, false, 50, 50), '165.02', 'refresh rate treats the threshold as inclusive')
assertEqual(refresh.targetRate(panel, false, 49, 50), '60.01', 'refresh rate runs slow on mains below the threshold')
assertEqual(refresh.targetRate(panel, true, 90, 50), '60.01', 'refresh rate runs slow on battery at any charge')
// A dead gauge should not pin a plugged-in laptop to its slowest rate forever.
assertEqual(refresh.targetRate(panel, false, -1, 50), '165.02', 'refresh rate runs fast on mains with an unreadable battery')
assertEqual(refresh.targetRate(external, true, 10, 50), '59.95', 'refresh rate still resolves a rate for any monitor asked about')

const singleRate = { name: 'eDP-1', width: 1920, height: 1080, availableModes: ['1920x1080@60.00Hz'] }
assertEqual(refresh.targetRate(singleRate, false, 90, 50), '', 'refresh rate declines a display with nothing to choose')

// Hyprland reports 165.02000 for the mode written as 165.02.
assertEqual(refresh.needsChange({ refreshRate: 165.02 }, '165.02'), false, 'refresh rate leaves a matching rate alone')
assertEqual(refresh.needsChange({ refreshRate: 60.008 }, '165.02'), true, 'refresh rate changes a mismatched rate')
assertEqual(refresh.needsChange({ refreshRate: 143.912 }, '143.91'), false, 'refresh rate compares on the rounded value')

assertEqual(
  refresh.monitorSpec(panel, '165.02'),
  'hl.monitor({ output = "eDP-1", mode = "2560x1600@165.02", position = "0x0", scale = 1.6 })',
  'refresh rate keeps the position and scale it found'
)
assertEqual(
  refresh.monitorSpec({ name: 'eDP-1"; os.execute("x")', width: 1, height: 1, x: 0, y: 0, scale: 1 }, '60'),
  '',
  'refresh rate refuses an output name it would have to quote'
)

// The whole decision, over a real two-display laptop.
assertEqual(
  refresh.pendingSpecs([panel, external], false, 80, 50).join('\n'),
  'hl.monitor({ output = "eDP-1", mode = "2560x1600@165.02", position = "0x0", scale = 1.6 })',
  'refresh rate drives the internal panel and leaves the external alone'
)
assertEqual(
  refresh.pendingSpecs([{ ...panel, refreshRate: 165.02 }, external], false, 80, 50).length,
  0,
  'refresh rate does nothing when the panel is already on the right rate'
)
assertEqual(
  refresh.pendingSpecs([{ ...panel, disabled: true }], false, 80, 50).length,
  0,
  'refresh rate skips a disabled panel'
)
assertEqual(refresh.pendingSpecs(null, false, 80, 50).length, 0, 'refresh rate handles a missing monitor list')
JS
