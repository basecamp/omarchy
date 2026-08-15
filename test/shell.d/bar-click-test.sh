#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')

// bar.run() starts a login shell on purpose (see shell-launch-test.sh), so
// click handlers that can reach their target in process must stay off it.
const menuQml = fs.readFileSync(
  path.join(root, 'shell/plugins/menu/BarWidget.qml'), 'utf8')

assert(
  /onPressed:[\s\S]*?root\.bar\.shell\.toggle\("omarchy\.menu"/.test(menuQml),
  'menu widget toggles the menu plugin in process'
)

JS
