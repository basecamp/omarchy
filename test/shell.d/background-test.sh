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

// The wallpaper is decoded at the screen's physical size, never at the size
// the file was shipped at, and never at native size first.
assert(
  backgroundQml.includes('readonly property bool sized: width > 0 && height > 0') &&
    backgroundQml.includes('readonly property int decodeWidth: sized ? Math.ceil(width * screen.devicePixelRatio) : 0') &&
    backgroundQml.includes('readonly property int decodeHeight: sized ? Math.ceil(height * screen.devicePixelRatio) : 0'),
  'background derives its decode size from the screen in physical pixels'
)

const count = (needle) => backgroundQml.split(needle).length - 1
assertEqual(count('sourceSize.width: panel.decodeWidth'), 3, 'all three wallpaper images bound their decode width to the screen')
assertEqual(count('sourceSize.height: panel.decodeHeight'), 3, 'all three wallpaper images bound their decode height to the screen')
assertEqual(count('source: panel.sized ? root.imageUrl('), 3, 'all three wallpaper images wait for the window size before loading')
JS
