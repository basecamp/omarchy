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
JS

run_node_test <<'JS'
const fs = require('fs')

const backgroundQml = fs.readFileSync(path.join(root, 'shell/plugins/background/Background.qml'), 'utf8')

assert(
  /sourceSize\.width: Math\.ceil\(width \* Screen\.devicePixelRatio \* 1\.6\)/.test(backgroundQml) &&
    /sourceSize\.height: Math\.ceil\(height \* Screen\.devicePixelRatio \* 1\.6\)/.test(backgroundQml),
  'background decodes the wallpaper to the screen size rather than the file size'
)

assert(
  (backgroundQml.match(/sourceSize\.width: base\.sourceSize\.width/g) || []).length === 2 &&
    (backgroundQml.match(/sourceSize\.height: base\.sourceSize\.height/g) || []).length === 2,
  'background transition frames decode at the same size as the wallpaper they cross-fade'
)

const images = backgroundQml.split(/\bImage\s*\{/).slice(1)
assert(
  images.length === 3 && images.every(image => image.includes('sourceSize.width') && image.includes('sourceSize.height')),
  'every background Image caps its decode size'
)
JS
