#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const shellQml = fs.readFileSync(path.join(root, 'shell/shell.qml'), 'utf8')

assert(
  /readonly property bool sessionLocked:[\s\S]*firstPartyServiceFor\("omarchy\.lock"\)[\s\S]*lockService\.locked/.test(shellQml),
  'plugin reload state follows the built-in lock service'
)

const reloadStart = shellQml.indexOf('function reloadPlugins()')
const reloadEnd = shellQml.indexOf('function finishPluginReload()', reloadStart)
assert(reloadStart !== -1 && reloadEnd !== -1, 'the plugin reload lifecycle is present')

const reloadFunction = shellQml.slice(reloadStart, reloadEnd)
const lockGuard = reloadFunction.indexOf('if (shell.sessionLocked)')
const serviceUnload = reloadFunction.indexOf('shell.unloadPluginServices()')
assert(
  lockGuard !== -1 && serviceUnload !== -1 && lockGuard < serviceUnload,
  'an active session lock is checked before plugin services are unloaded'
)

assert(
  /if \(shell\.sessionLocked\) \{[\s\S]*shell\.pluginReloadDeferredForLock = true[\s\S]*return[\s\S]*\}/.test(reloadFunction),
  'a plugin reload is queued instead of destroying an active lock client'
)

assert(
  /onSessionLockedChanged:[\s\S]*if \(shell\.sessionLocked \|\| !shell\.pluginReloadDeferredForLock\) return[\s\S]*shell\.pluginReloadDeferredForLock = false[\s\S]*Qt\.callLater\(shell\.reloadPlugins\)/.test(shellQml),
  'the queued plugin reload runs after the session unlocks'
)
JS
