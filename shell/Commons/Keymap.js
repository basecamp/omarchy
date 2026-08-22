.pragma library

// Keybindings for panels that navigate a list.
//
// Bindings are written as human-readable specs ("Down", "Ctrl+N", "Shift+Tab")
// so they can live in shell.json, and every action takes a LIST of them, so
// several keys can drive the same action without the panel knowing which.
//
// Qt's key and modifier codes are stable public constants, repeated here so
// this file stays plain JS: it is imported by QML and by the Node test suite,
// which has no Qt available. keymap-test.sh pins the two codes that were
// verified against live key events.

var MODIFIER_CODES = {
  shift: 0x02000000,
  ctrl: 0x04000000,
  control: 0x04000000,
  alt: 0x08000000,
  meta: 0x10000000,
  super: 0x10000000
}

// Flags Qt adds to an event on its own (keypad keys, keyboard layout groups).
// No spec can name them, so they are ignored when matching.
var INTRINSIC_MODIFIERS = 0x20000000 | 0x40000000

var NAMED_KEY_CODES = {
  escape: 0x01000000,
  esc: 0x01000000,
  tab: 0x01000001,
  backtab: 0x01000002,
  backspace: 0x01000003,
  return: 0x01000004,
  enter: 0x01000005,
  insert: 0x01000006,
  delete: 0x01000007,
  del: 0x01000007,
  home: 0x01000010,
  end: 0x01000011,
  left: 0x01000012,
  up: 0x01000013,
  right: 0x01000014,
  down: 0x01000015,
  pageup: 0x01000016,
  pagedown: 0x01000017,
  space: 0x20
}

// Qt uses the ASCII code for letters and digits, so Key_N === 78. Anything
// else has to be a name from the table above; unknown names return -1 so a
// typo in shell.json disables that one binding instead of throwing.
function keyCode(name) {
  var token = String(name === undefined || name === null ? "" : name).trim()
  if (!token) return -1
  var named = NAMED_KEY_CODES[token.toLowerCase()]
  if (named !== undefined) return named
  if (token.length === 1) {
    var code = token.toUpperCase().charCodeAt(0)
    if ((code >= 48 && code <= 57) || (code >= 65 && code <= 90)) return code
  }
  return -1
}

// "Ctrl+Shift+N" -> { key: 78, modifiers: 0x06000000 }. Returns null when the
// key is unknown, so callers can treat a bad spec as simply not bound.
function parse(spec) {
  var text = String(spec === undefined || spec === null ? "" : spec).trim()
  if (!text) return null

  var parts = text.split("+")
  var keyToken = parts.pop()
  var modifiers = 0
  for (var i = 0; i < parts.length; i++) {
    var modifier = MODIFIER_CODES[parts[i].trim().toLowerCase()]
    if (modifier === undefined) return null
    modifiers |= modifier
  }

  var key = keyCode(keyToken)
  if (key < 0) return null
  return { key: key, modifiers: modifiers }
}

// True when the event matches any spec in bindings. Nameable modifiers must
// match exactly, so Ctrl+Shift+N never fires a Ctrl+N binding and bare letters
// keep falling through to the filter.
function matches(event, bindings) {
  if (!event || !bindings) return false
  var specs = typeof bindings === "string" ? [bindings] : bindings
  if (!Array.isArray(specs)) return false

  var key = event.key
  var modifiers = event.modifiers & ~INTRINSIC_MODIFIERS
  // Shift+Tab arrives as Key_Backtab. Fold it back to Tab+Shift so the spec
  // people naturally write matches; "Backtab" is normalised the same way.
  if (key === NAMED_KEY_CODES.backtab) {
    key = NAMED_KEY_CODES.tab
    modifiers |= MODIFIER_CODES.shift
  }

  for (var i = 0; i < specs.length; i++) {
    var binding = parse(specs[i])
    if (!binding) continue
    if (binding.key === NAMED_KEY_CODES.backtab) {
      binding.key = NAMED_KEY_CODES.tab
      binding.modifiers |= MODIFIER_CODES.shift
    }
    if (binding.key === key && binding.modifiers === modifiers) return true
  }
  return false
}

// Overlay a user's shell.json block onto a panel's defaults, one action at a
// time, so overriding "down" does not silently drop "up". A bare string is
// accepted wherever a list is, since binding one key is the common case.
function resolve(userConfig, defaults) {
  var out = {}
  var action

  for (action in defaults) {
    if (defaults.hasOwnProperty(action)) out[action] = defaults[action].slice()
  }
  if (!userConfig || typeof userConfig !== "object" || Array.isArray(userConfig)) return out

  for (action in userConfig) {
    if (!userConfig.hasOwnProperty(action)) continue
    var value = userConfig[action]
    if (typeof value === "string") {
      out[action] = value ? [value] : []
    } else if (Array.isArray(value)) {
      out[action] = value.filter(function(spec) { return typeof spec === "string" && spec })
    }
  }
  return out
}
