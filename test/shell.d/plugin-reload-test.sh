#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')

const shellSource = fs.readFileSync(path.join(root, 'shell/shell.qml'), 'utf8')

function functionBody(source, name) {
  const marker = `function ${name}(`
  const start = source.indexOf(marker)
  if (start === -1) throw new Error(`missing ${name}`)

  const open = source.indexOf('{', start)
  let depth = 0
  let quote = ''
  let escaped = false
  let lineComment = false
  let blockComment = false
  for (let index = open; index < source.length; index += 1) {
    const char = source[index]
    const next = source[index + 1]

    if (lineComment) {
      if (char === '\n') lineComment = false
      continue
    }
    if (blockComment) {
      if (char === '*' && next === '/') {
        blockComment = false
        index += 1
      }
      continue
    }
    if (quote) {
      if (escaped) escaped = false
      else if (char === '\\') escaped = true
      else if (char === quote) quote = ''
      continue
    }
    if (char === '/' && next === '/') {
      lineComment = true
      index += 1
      continue
    }
    if (char === '/' && next === '*') {
      blockComment = true
      index += 1
      continue
    }
    if (char === '"' || char === "'" || char === '`') {
      quote = char
      continue
    }
    if (char === '{') depth += 1
    if (char === '}') depth -= 1
    if (depth === 0) return source.slice(open + 1, index)
  }

  throw new Error(`unterminated ${name}`)
}

const destroyed = []
const firstPartyLock = { destroy: () => destroyed.push('omarchy.lock') }
const firstPartyIdle = { destroy: () => destroyed.push('omarchy.idle') }
const localService = { destroy: () => destroyed.push('local.service') }
let _services = {
  'omarchy.lock': firstPartyLock,
  'omarchy.idle': firstPartyIdle,
  'local.service': localService
}
const pluginRegistry = {
  installedPlugins: {
    'omarchy.lock': { __isFirstParty: true },
    'omarchy.idle': { __isFirstParty: true },
    'local.service': { __isFirstParty: false }
  }
}

function unloadServices(keepFirstParty) {
  new Function(
    'pluginRegistry',
    'services',
    'setServices',
    'keepFirstParty',
    `let _services = services\n${functionBody(shellSource, 'unloadPluginServices')}\nsetServices(_services)`
  )(pluginRegistry, _services, value => { _services = value }, keepFirstParty)
}

unloadServices(true)

assertDeepEqual(destroyed, ['local.service'], 'local plugin reload destroys only third-party services')
assertDeepEqual(Object.keys(_services).sort(), ['omarchy.idle', 'omarchy.lock'], 'local plugin reload retains first-party infrastructure services')
assert(_services['omarchy.lock'] === firstPartyLock, 'local plugin reload preserves the active lock service instance')

destroyed.length = 0
_services['local.service'] = localService
unloadServices(false)

assertDeepEqual(destroyed.sort(), ['local.service', 'omarchy.idle', 'omarchy.lock'], 'explicit plugin rescan destroys every service')
assertDeepEqual(Object.keys(_services), [], 'explicit plugin rescan retains no stale service instances')
JS
