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

const wallpaper = {}
require('vm').runInNewContext(fs.readFileSync(path.join(root, 'shell/plugins/background/Wallpaper.js'), 'utf8'), wallpaper)
const config = {monitors: {'DP-1': '~/main.jpg'}, portrait: '/portrait.jpg', landscape: '/landscape.jpg'}
assert(wallpaper.select(config, 'DP-1', 1080, 1920, '/home/test') === '/home/test/main.jpg', 'named wallpaper takes precedence and expands home')
assert(wallpaper.select(config, 'DP-2', 1080, 1920, '') === '/portrait.jpg', 'vertical displays use the portrait default')
assert(wallpaper.select(config, 'DP-2', 1920, 1080, '') === '/landscape.jpg', 'horizontal displays use the landscape default')
assert(wallpaper.select({}, 'DP-1', 1920, 1080, '') === '', 'unconfigured displays use the theme wallpaper')
assert(wallpaper.select({monitors: {'DP-1': 'relative.jpg'}}, 'DP-1', 1920, 1080, '') === '', 'invalid override paths use the theme wallpaper')
JS
