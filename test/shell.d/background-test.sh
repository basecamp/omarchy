#!/bin/bash
source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const background = requireFromRoot('shell/plugins/background/BackgroundModel.js')

const backgroundQml = fs.readFileSync(path.join(root, 'shell/plugins/background/Background.qml'), 'utf8')

const lowMemoryLimitKiB = 4 * 1024 * 1024
assertEqual(background.parseAvailableMemoryKiB('MemTotal: 8 kB\nMemAvailable: 4194303 kB\n'), 4194303, 'background parses MemAvailable')
assertEqual(background.parseAvailableMemoryKiB('MemTotal: 8 kB\n'), -1, 'background rejects missing MemAvailable')
assertEqual(background.parseAvailableMemoryKiB('MemAvailable: unknown kB\n'), -1, 'background rejects malformed MemAvailable')
assert(background.isLowMemory(lowMemoryLimitKiB - 1, lowMemoryLimitKiB), 'background detects memory below 4 GiB')
assert(!background.isLowMemory(lowMemoryLimitKiB, lowMemoryLimitKiB), 'background accepts memory equal to 4 GiB')
assert(!background.isLowMemory(lowMemoryLimitKiB + 1, lowMemoryLimitKiB), 'background accepts memory above 4 GiB')
assert(!background.isLowMemory(-1, lowMemoryLimitKiB), 'background falls back for unavailable memory')

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
    backgroundQml.includes('path: "/proc/meminfo"') &&
    backgroundQml.includes('BackgroundModel.parseAvailableMemoryKiB(raw)') &&
    backgroundQml.includes('BackgroundModel.isLowMemory(availableMemoryKiB, lowMemoryLimitKiB)'),
  'background uses tested memory parsing and threshold logic'
)

assert(
  (backgroundQml.match(/sourceSize: root\.lowMemory/g) || []).length === 3 &&
    backgroundQml.includes('Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))') &&
    (backgroundQml.match(/fillMode: Image\.PreserveAspectCrop/g) || []).length === 3 &&
    backgroundQml.includes(': undefined'),
  'background uses crop-aware bounded decoding for all wallpaper frames only while memory is low'
)

assert(
  backgroundQml.includes('if (memoryReady) return') &&
    backgroundQml.includes('Component.onCompleted: refreshBackground()') &&
    !backgroundQml.includes('memoryFile.reload()'),
  'background makes one startup memory decision from the FileView preload'
)
JS
