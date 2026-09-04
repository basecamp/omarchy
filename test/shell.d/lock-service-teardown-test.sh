#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const shellQml = fs.readFileSync(path.join(root, 'shell/shell.qml'), 'utf8')
const lockQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

// An adjacency regex (`anchor[\s\S]*?anchor`) only proves that one occurrence
// follows another. It cannot prove that a destructive call does not *precede*
// the guard meant to stop it, which is the only thing that matters here: a
// destroy hoisted above the guard leaves the guard reading as present and doing
// nothing. Every ordering claim below is therefore made against a brace-matched
// function body, comparing the index of the guard against the index of the
// first destroy in that body.
function bodyOf(src, name, label) {
  const start = src.indexOf(`function ${name}(`)
  if (start === -1) fail(`${label}: source defines ${name}()`)
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

// ------------------------------------------------------------- _syncServices()
// unloadPluginServices() spares a keepLoaded service, so a plugin hot-reload no
// longer destroys the lock. _syncServices destroys services inline on its own,
// without going through unloadPluginServices() and without consulting
// keepLoaded, whenever the registry stops listing a plugin as installed,
// enabled and service-declaring. It is reached straight from pluginsChanged, so
// `omarchy plugin disable omarchy.lock` gets there with no reload at all.
const sync = bodyOf(shellQml, '_syncServices', 'sync guard')
const syncDestroy = sync.indexOf('.destroy()')

// Finding the property name is not enough: `inst.sessionLockOwned !== true`
// reads as present, sits before the destroy, and continues on exactly the
// services this guard exists for. Compare the whole condition.
const syncGuardMatch = sync.match(/if \((.+?)\) continue\s*\n\s*if \(inst && typeof inst\.destroy/)
assert(syncGuardMatch, '_syncServices guards the destroy with a skip that continues')
assertEqual(
  syncGuardMatch[1].trim(),
  'inst && inst.sessionLockOwned === true',
  'the skip fires when the instance owns the session lock -- not negated, not widened'
)
const syncGuard = syncGuardMatch.index

assert(syncDestroy !== -1, '_syncServices still destroys services for plugins that went away')
assert(
  syncGuard < syncDestroy,
  'no destroy in _syncServices runs before the ownership skip',
  `skip at ${syncGuard}, first destroy at ${syncDestroy}`
)

// Duck-typed, not keyed on the first-party plugin id, so a cloned lock plugin
// is covered as well. Comments are stripped so the prose above the guard, which
// names the id as an example, does not answer for the code.
const syncCode = sync.replace(/\/\/[^\n]*/g, '')
assert(
  !/omarchy\.lock/.test(syncCode),
  '_syncServices does not key the skip on the first-party lock id'
)

// ------------------------------------------------- lock service: sessionLockOwned
// The signal the shell reads must be deterministic on a rebuilt service.
// sessionLock.secure resolves through the process-wide session-lock manager,
// which an earlier teardown can leave dangling, so the ownership property must
// not depend on it -- unlike `locked`, which deliberately still does.
const decl = lockQml.match(/readonly property bool sessionLockOwned:([^\n]*)/)
assert(decl, 'the lock service exposes sessionLockOwned for the shell to read')

const expr = decl[1].replace(/\/\/.*$/, '').replace(/\s+/g, ' ').trim()
const operands = expr.split('||').map((s) => s.trim()).sort()

// Token presence is not enough. `lockRequested && sessionLock.locked` contains
// both names and means the opposite; a `secure` term laundered through a helper
// property keeps the word off this line entirely. Compare the operand set.
assertEqual(
  JSON.stringify(operands),
  JSON.stringify(['lockRequested', 'sessionLock.locked']),
  'sessionLockOwned is exactly lockRequested OR sessionLock.locked -- no extra term, no conjunction'
)
assert(!/\bsecure\b/.test(expr), 'sessionLockOwned does not read sessionLock.secure')
JS
