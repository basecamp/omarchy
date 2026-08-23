#!/bin/bash
source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')

const backgroundQml = fs.readFileSync(path.join(root, 'shell/plugins/background/Background.qml'), 'utf8')

assert(
  /theme=\$\(omarchy-theme-switcher\); \[\[ -n \$theme \]\] && omarchy-theme-set \\"\$theme\\" >\/dev\/null 2>&1 &/.test(backgroundQml),
  'background theme switcher starts theme application asynchronously after selection'
)

assert(
  backgroundQml.includes('pendingThemeFallbackTimer.restart()') &&
    backgroundQml.includes('pendingThemeFallbackTimer.stop()') &&
    backgroundQml.includes('id: pendingThemeFallbackTimer') &&
    !backgroundQml.includes('pendingThemeVersion !== backgroundVersion'),
  'background theme transition applies pending colors even if image reveal stalls'
)

assert(
  backgroundQml.includes('lowMemoryLimitKiB: 4 * 1024 * 1024') &&
    backgroundQml.includes('lowMemoryDownscaleFactor: 16') &&
    backgroundQml.includes('path: "/proc/meminfo"') &&
    backgroundQml.includes('MemAvailable:') &&
    backgroundQml.includes('availableMemoryKiB < lowMemoryLimitKiB'),
  'background detects low memory from MemAvailable below 4 GiB'
)

assert(
  (backgroundQml.match(/sourceSize: root\.lowMemory/g) || []).length === 3 &&
    backgroundQml.includes('root.lowMemorySourceSize(width, height, Screen.devicePixelRatio)') &&
    backgroundQml.includes(': undefined'),
  'background bounds all wallpaper frames only while memory is low'
)
JS
