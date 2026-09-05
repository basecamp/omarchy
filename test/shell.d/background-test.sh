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
  backgroundQml.includes('command: ["omarchy-menu", "toggle", "apps"]') &&
    /id: appsMenuTimer\s+interval: Qt\.styleHints\.mouseDoubleClickInterval\s+onTriggered: root\.openAppsMenu\(\)/.test(backgroundQml) &&
    /onClicked: function\(mouse\) \{\s+if \(mouse\.button === Qt\.RightButton\) appsMenuTimer\.restart\(\)/.test(backgroundQml) &&
    /onDoubleClicked: function\(mouse\) \{\s+appsMenuTimer\.stop\(\)/.test(backgroundQml),
  'right click on the desktop opens the apps menu once the double-click interval has passed'
)

assert(
  backgroundQml.includes('pendingThemeFallbackTimer.restart()') &&
    backgroundQml.includes('pendingThemeFallbackTimer.stop()') &&
    backgroundQml.includes('id: pendingThemeFallbackTimer') &&
    !backgroundQml.includes('pendingThemeVersion !== backgroundVersion'),
  'background theme transition applies pending colors even if image reveal stalls'
)
JS
