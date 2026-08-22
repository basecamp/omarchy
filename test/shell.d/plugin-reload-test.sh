#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')

const shell = fs.readFileSync(path.join(root, 'shell/shell.qml'), 'utf8')
const rescan = shell.match(/function rescanPlugins\(\): void \{([\s\S]*?)\n    \}/)
const discover = shell.match(/function discoverPlugins\(id: string\): void \{([\s\S]*?)\n    \}/)

assert(rescan, 'shell exposes plugin code reload over IPC')
assert(
  /shell\.reloadPlugins\(\)/.test(rescan[1]),
  'explicit code reloads retain the full plugin teardown path'
)
assert(discover, 'shell exposes plugin discovery over IPC')
assert(
  /watcherPluginDiscoveries/.test(discover[1])
    && /knownLocalPluginIds/.test(discover[1])
    && /shell\.reloadPlugins\(\)/.test(discover[1])
    && /shell\.pluginRegistry\.rescan\(\)/.test(discover[1]),
  'plugin discovery is idempotent and same-id reinstalls use code reload semantics'
)

const localChange = shell.match(/function onLocalPluginChanged\(pluginId\) \{([\s\S]*?)\n    \}/)
assert(localChange, 'shell handles local plugin filesystem changes')
assert(
  /!shell\.knownLocalPluginIds\[pluginId\]/.test(localChange[1])
    && /rememberLocalPlugin\(pluginId\)/.test(localChange[1])
    && /shell\.pluginRegistry\.rescan\(\)/.test(localChange[1]),
  'new plugin directories use discovery without global teardown'
)
assert(
  /localPluginReloadTimer\.restart\(\)/.test(localChange[1]),
  'changes to installed plugins retain debounced code reload'
)

const add = fs.readFileSync(path.join(root, 'bin/omarchy-plugin-add'), 'utf8')
assert(
  /omarchy-shell shell discoverPlugins "\$id"/.test(add),
  'plugin add requests targeted metadata discovery for its installed id'
)
JS
