#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const shellQml = fs.readFileSync(path.join(root, 'shell/shell.qml'), 'utf8')

function bodyOf(src, name, label) {
  const start = src.indexOf(`function ${name}(`)
  assert(start !== -1, `${label}: source defines ${name}()`)
  const open = src.indexOf('{', start)
  let depth = 0
  for (let i = open; i < src.length; i++) {
    if (src[i] === '{') depth += 1
    else if (src[i] === '}') {
      depth -= 1
      if (depth === 0) return src.slice(open + 1, i)
    }
  }
  fail(`${label}: ${name}() has balanced braces`)
}

function firstIndexOf(body, needles) {
  const found = needles.map((needle) => body.indexOf(needle)).filter((index) => index !== -1)
  return found.length ? Math.min(...found) : -1
}

const owned = bodyOf(shellQml, 'sessionLockOwned', 'ownership scan')
assert(
  /for \(var id in _services\)/.test(owned) && /inst\.sessionLockOwned === true/.test(owned),
  'lock ownership is duck-typed across every service'
)
assert(!owned.includes('omarchy.lock'), 'lock ownership is not tied to the built-in plugin id')

const reload = bodyOf(shellQml, 'reloadPlugins', 'reload guard')
const teardown = firstIndexOf(reload, [
  'shell.pluginReloading = true',
  'shell.unloadPanels()',
  'shell.unloadPluginServices()',
  'shell.unloadPluginWidgets()',
])
const guard = reload.match(/if \(([^)]+\(\))\) \{\s*shell\.armLocalPluginReload\(\)\s*return/)
assert(guard, 'reloadPlugins defers with a guard that re-arms the reload')
assertEqual(guard[1], 'shell.sessionLockOwned()', 'the reload guard fires on owned locks')
assert(teardown !== -1, 'unlocked reloads still tear down plugin state')
assert(guard.index < teardown, 'the lock guard runs before every reload teardown')
assert(
  reload.indexOf('localPluginReloadTimer.stop()') > guard.index &&
    reload.indexOf('localPluginReloadTimer.stop()') < teardown,
  'a proceeding reload cancels any deferred timer before teardown'
)

const arm = bodyOf(shellQml, 'armLocalPluginReload', 'reload timer arming')
const intervals = arm.match(/interval = shell\.sessionLockOwned\(\) \? (\d+) : (\d+)/)
assert(intervals, 'the timer interval is selected from current lock ownership')
assert(Number(intervals[1]) >= 1000, 'a locked session is polled slowly')
assert(Number(intervals[2]) >= 50 && Number(intervals[2]) <= 500, 'an unlocked edit retains a short debounce')
assertEqual(
  (shellQml.match(/localPluginReloadTimer\.restart\(\)/g) || []).length,
  1,
  'every reload-timer arming goes through the interval-aware helper'
)

const localChange = bodyOf(shellQml, 'onLocalPluginChanged', 'local plugin watcher')
assert(localChange.includes('shell.armLocalPluginReload()'), 'local file changes use the guarded timer helper')

const sync = bodyOf(shellQml, '_syncServices', 'service synchronization')
const syncGuard = sync.indexOf('inst && inst.sessionLockOwned === true')
const syncDestroy = sync.indexOf('.destroy()')
assert(syncGuard !== -1, '_syncServices retains a lock-owning service')
assert(syncDestroy !== -1, '_syncServices still destroys ordinary removed services')
assert(syncGuard < syncDestroy, '_syncServices checks ownership before destroying a service')
assert(
  sync.slice(syncGuard, syncDestroy).includes('shell.armLocalPluginReload()') &&
    sync.slice(syncGuard, syncDestroy).includes('continue'),
  'a retained removed service is collected by a deferred reload after unlock'
)

const unload = bodyOf(shellQml, 'unloadPluginServices', 'service unload')
const unloadGuard = unload.indexOf('inst && inst.sessionLockOwned === true')
const unloadDestroy = unload.indexOf('.destroy()')
assert(unloadGuard !== -1 && unloadGuard < unloadDestroy, 'the low-level unload also protects an owned lock')
assert(
  unload.slice(unloadGuard, unloadDestroy).includes('next[existingId] = inst') &&
    unload.slice(unloadGuard, unloadDestroy).includes('continue'),
  'the protected lock instance remains registered with the shell'
)
JS
