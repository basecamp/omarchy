#!/bin/bash
source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const vm = require('vm')

const source = fs.readFileSync(path.join(root, 'shell/Commons/Keymap.js'), 'utf8').replace(/^\.pragma library\n/, '')
const keymap = {}
vm.createContext(keymap)
vm.runInContext(source, keymap)

// Pinned against key events captured from a running menu, so a wrong constant
// in the table fails here rather than silently unbinding a key in the UI.
assertDeepEqual(
  keymap.parse('Ctrl+N'),
  { key: 78, modifiers: 0x04000000 },
  'Ctrl+N parses to the Qt codes a live event carries'
)
assertDeepEqual(
  keymap.parse('Down'),
  { key: 0x01000015, modifiers: 0 },
  'a bare named key parses with no modifiers'
)
assertDeepEqual(
  keymap.parse('Ctrl+Shift+Tab'),
  { key: 0x01000001, modifiers: 0x04000000 | 0x02000000 },
  'modifiers combine into one mask'
)

assert(keymap.parse('Ctrl+n').key === 78, 'key names are case-insensitive')
assert(keymap.parse('CTRL+N').modifiers === 0x04000000, 'modifier names are case-insensitive')
assert(keymap.parse('Super+K').modifiers === 0x10000000, 'Super is an alias for Meta')

// A typo should cost one binding, not throw inside a key handler.
assertEqual(keymap.parse('Ctrl+Nope'), null, 'an unknown key name parses to null')
assertEqual(keymap.parse('Hyper+N'), null, 'an unknown modifier parses to null')
assertEqual(keymap.parse(''), null, 'an empty spec parses to null')
assertEqual(keymap.parse('Ctrl+'), null, 'a spec with no key parses to null')
assertEqual(keymap.parse('Ctrl++'), null, 'punctuation keys are not bindable')
assertEqual(keymap.parse(null), null, 'a null spec parses to null')

const down = ['Down', 'Ctrl+N', 'Ctrl+J']
assert(keymap.matches({ key: 0x01000015, modifiers: 0 }, down), 'Down matches the down action')
assert(keymap.matches({ key: 78, modifiers: 0x04000000 }, down), 'Ctrl+N matches the same action')
assert(keymap.matches({ key: 74, modifiers: 0x04000000 }, down), 'Ctrl+J matches the same action')
assert(!keymap.matches({ key: 80, modifiers: 0x04000000 }, down), 'Ctrl+P does not match the down action')

// Exact modifier equality keeps bare letters falling through to the filter and
// stops Ctrl+Shift+N stealing a Ctrl+N binding.
assert(!keymap.matches({ key: 78, modifiers: 0 }, down), 'a bare letter does not match a Ctrl binding')
assert(
  !keymap.matches({ key: 78, modifiers: 0x04000000 | 0x02000000 }, down),
  'an extra modifier does not match'
)
// Qt tags keypad keys with KeypadModifier and layout-group keys with
// GroupSwitchModifier. Neither is something a user can write in a spec, so
// they must not stop numpad Enter or keypad arrows matching their plain names.
assert(
  keymap.matches({ key: 0x01000005, modifiers: 0x20000000 }, ['Enter']),
  'numpad Enter matches a plain Enter binding'
)
assert(
  keymap.matches({ key: 0x01000013, modifiers: 0x20000000 }, ['Up']),
  'a keypad arrow matches a plain arrow binding'
)
assert(
  keymap.matches({ key: 78, modifiers: 0x04000000 | 0x40000000 }, down),
  'a layout-group flag does not stop Ctrl+N matching'
)
assert(
  !keymap.matches({ key: 0x01000005, modifiers: 0x20000000 | 0x04000000 }, ['Enter']),
  'a keypad key with a real modifier still needs that modifier in the spec'
)
// Shift+Tab reaches Qt as Key_Backtab rather than Key_Tab, so the spec people
// naturally write has to match the event they actually get.
assert(
  keymap.matches({ key: 0x01000002, modifiers: 0x02000000 }, ['Shift+Tab']),
  'Shift+Tab matches the Backtab event Qt delivers for it'
)
assert(
  keymap.matches({ key: 0x01000002, modifiers: 0x02000000 }, ['Backtab']),
  'a bare Backtab spec matches the same event'
)
assert(
  !keymap.matches({ key: 0x01000001, modifiers: 0 }, ['Shift+Tab']),
  'plain Tab does not match Shift+Tab'
)
assert(keymap.matches({ key: 78, modifiers: 0x04000000 }, 'Ctrl+N'), 'a bare string is accepted as one binding')
assert(!keymap.matches({ key: 78, modifiers: 0x04000000 }, null), 'no bindings never matches')

const defaults = { up: ['Up'], down: ['Down'], close: ['Escape'] }

assertDeepEqual(keymap.resolve(null, defaults), defaults, 'no user config returns the defaults')
assertDeepEqual(
  keymap.resolve({ down: ['Down', 'Ctrl+N'] }, defaults),
  { up: ['Up'], down: ['Down', 'Ctrl+N'], close: ['Escape'] },
  'overriding one action leaves the others intact'
)
assertDeepEqual(
  keymap.resolve({ up: 'Ctrl+P' }, defaults),
  { up: ['Ctrl+P'], down: ['Down'], close: ['Escape'] },
  'a bare string overrides as a single binding'
)
assertDeepEqual(
  keymap.resolve({ close: [] }, defaults),
  { up: ['Up'], down: ['Down'], close: [] },
  'an empty list unbinds an action'
)
assertDeepEqual(
  keymap.resolve({ down: [null, 'Ctrl+N', ''] }, defaults),
  { up: ['Up'], down: ['Ctrl+N'], close: ['Escape'] },
  'non-string entries are dropped'
)

const frozen = { up: ['Up'] }
keymap.resolve({}, frozen).up.push('Ctrl+P')
assertDeepEqual(frozen, { up: ['Up'] }, 'resolve copies the defaults instead of aliasing them')
JS
