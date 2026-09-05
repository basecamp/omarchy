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
// it was shipped at, unless it is smaller than the screen: then it is decoded
// at its own size instead of being scaled up to cover the screen.
assert(
  backgroundQml.includes('readonly property bool sized: width > 0 && height > 0') &&
    backgroundQml.includes('readonly property int decodeWidth: sized ? Math.ceil(width * screen.devicePixelRatio) : 0') &&
    backgroundQml.includes('readonly property int decodeHeight: sized ? Math.ceil(height * screen.devicePixelRatio) : 0'),
  'background derives its decode size from the screen in physical pixels'
)
assert(
  backgroundQml.includes('["magick", "identify", "-ping", "-format", "%w %h", sizeProbe.path]') &&
    backgroundQml.includes('if (native.width > 0 && (native.width < decodeWidth || native.height < decodeHeight)) return Qt.size(native.width, native.height)'),
  'background reads the wallpaper header and never decodes larger than the native size'
)
const count = (needle) => backgroundQml.split(needle).length - 1
assertEqual(count('sourceSize.width: decode.width'), 3, 'all three wallpaper images bind their decode width')
assertEqual(count('sourceSize.height: decode.height'), 3, 'all three wallpaper images bind their decode height')
assertEqual(count('source: decode.width > 0 ? root.imageUrl('), 3, 'all three wallpaper images wait for the screen and native sizes before loading')
JS
