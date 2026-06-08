#!/bin/bash
source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')

const menuQml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')
const launcherQml = fs.readFileSync(path.join(root, 'shell/plugins/launcher/Launcher.qml'), 'utf8')

assert(
  /rowReservedBorderLeft:\s*Border\.left\(selectedBorderSpec\)/.test(menuQml)
    && /rowReservedBorderRight:\s*Border\.right\(selectedBorderSpec\)/.test(menuQml),
  'Menu rows reserve selected border insets'
)

assert(
  !/anchors\.(left|right)Margin:[^\n]*\brow\.border(Left|Right)\b/.test(menuQml),
  'Menu row content does not depend on current selected border state'
)

assert(
  /rowReservedBorderLeft:\s*Border\.left\(selectedBorderSpec\)/.test(launcherQml)
    && /rowReservedBorderRight:\s*Border\.right\(selectedBorderSpec\)/.test(launcherQml),
  'Launcher rows reserve selected border insets'
)

assert(
  !/anchors\.(left|right)Margin:[^\n]*\brow\.border(Left|Right)\b/.test(launcherQml),
  'Launcher row content does not depend on current selected border state'
)
JS
