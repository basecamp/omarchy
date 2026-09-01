#!/bin/bash
source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')

const backgroundQml = fs.readFileSync(path.join(root, 'shell/plugins/background/Background.qml'), 'utf8')

assert(
  /read -r theme background < <\(omarchy-theme-switcher\); \[\[ -n \$theme \]\] && omarchy-theme-set \\"\$theme\\" \\"\$background\\" >\/dev\/null 2>&1 &/.test(backgroundQml),
  'background theme switcher applies the picked theme and background asynchronously after selection'
)

assert(
  backgroundQml.includes('pendingThemeFallbackTimer.restart()') &&
    backgroundQml.includes('pendingThemeFallbackTimer.stop()') &&
    backgroundQml.includes('id: pendingThemeFallbackTimer') &&
    !backgroundQml.includes('pendingThemeVersion !== backgroundVersion'),
  'background theme transition applies pending colors even if image reveal stalls'
)
JS
