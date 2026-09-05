#!/bin/bash

set -euo pipefail

# A shell.toml role may name another role instead of a colour, and Color.qml
# resolves that by recursing. A theme ships shell.toml verbatim, so the chain
# has to be bounded: two roles naming each other is enough to exhaust the stack
# of the process that draws the desktop.
#
# flatColor is plain JavaScript inside the QML block, so lift it out and run it
# against a stubbed root rather than asserting on the source text.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const source = fs.readFileSync(root + '/shell/Commons/Color.qml', 'utf8')

function lift(name) {
  const match = source.match(new RegExp('\\n  function ' + name + '\\([\\s\\S]*?\\n  \\}\\n'))
  if (!match) fail('Color.qml still defines ' + name + '()')
  return match[0]
}

const depthMatch = source.match(/readonly property int maxAliasDepth:\s*(\d+)/)
assert(!!depthMatch, 'Color.qml declares a maximum alias depth')
const maxAliasDepth = Number(depthMatch[1])

// Stand-ins for the QML scope flatColor closes over.
const rootStub = {
  foreground: '#cacccc',
  background: '#101315',
  accent: '#cacccc',
  urgent: '#a55555',
  muted: '#707880',
  maxAliasDepth: maxAliasDepth,
  shellValues: {}
}
const Qt = { rgba: (r, g, b, a) => 'rgba(' + [r, g, b, a].join(',') + ')' }
const Geometry = { canonicalColor: (token) => token }

const build = new Function('root', 'Qt', 'Geometry', `
  ${lift('firstColorToken')}
  ${lift('flatColor')}
  return { firstColorToken: firstColorToken, flatColor: flatColor }
`)
const color = build(rootStub, Qt, Geometry)

const FALLBACK = '#fallback'

// A role naming a real colour resolves.
rootStub.shellValues = { 'bar.background': '#123456' }
assertEqual(color.flatColor('bar.background', FALLBACK), '#123456', 'a role pointing at a colour resolves to it')

// A short chain of aliases still resolves, so the bound is not too tight.
rootStub.shellValues = { 'a.one': 'a.two', 'a.two': 'a.three', 'a.three': '#abcdef' }
assertEqual(color.flatColor('a.one', FALLBACK), '#abcdef', 'a chain of aliases shorter than the bound still resolves')

// A role naming itself was already handled by the !== check, which stops the
// recursion and lets the value fall through as an unresolvable colour name.
rootStub.shellValues = { 'bar.background': 'bar.background' }
assertEqual(color.flatColor('bar.background', FALLBACK), FALLBACK, 'a role naming itself resolves to the fallback')

// Two roles naming each other is the case the !== check misses. Before the
// depth bound this recursed until the stack gave out.
rootStub.shellValues = { 'bar.background': 'bar.text', 'bar.text': 'bar.background' }
let cycled
try {
  cycled = color.flatColor('bar.background', FALLBACK)
} catch (e) {
  fail('a two-role cycle in shell.toml resolves instead of exhausting the stack', String(e))
}
assertEqual(cycled, FALLBACK, 'a two-role cycle in shell.toml resolves to the fallback')

// A longer ring, in case someone raises the bound without rechecking.
const ring = {}
for (let i = 0; i < maxAliasDepth + 4; i++) ring['r.' + i] = 'r.' + ((i + 1) % (maxAliasDepth + 4))
rootStub.shellValues = ring
let ringed
try {
  ringed = color.flatColor('r.0', FALLBACK)
} catch (e) {
  fail('a long alias ring resolves instead of exhausting the stack', String(e))
}
assertEqual(ringed, FALLBACK, 'a longer alias ring also resolves to the fallback')

pass('shell.toml colour aliases cannot recurse without bound')
JS
