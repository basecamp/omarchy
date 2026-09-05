function stripJsonc(raw) {
  return String(raw || "")
    .replace(/^\s*\/\/[^\n]*(\n|$)/gm, "")
    .replace(/,(\s*[}\]])/g, "$1")
}

// Menu entries and keybindings come out of the same file, so both read it
// through here rather than each stripping and parsing it their own way.
// Anything that is not a JSON object — including a file that fails to parse —
// comes back null, and the caller falls back to contributing nothing.
function parseJsoncObject(raw) {
  var stripped = stripJsonc(raw)
  if (!stripped.trim()) return null

  var parsed
  try {
    parsed = JSON.parse(stripped)
  } catch (e) {
    return null
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) return null
  return parsed
}

// Top-level keys that configure the menu rather than declare a row.
var RESERVED_TOP_LEVEL_KEYS = { keybindings: true }

function normalizeAliases(value) {
  if (Array.isArray(value)) return value.filter(function(v) { return v })
  if (typeof value === "string" && value) return [value]
  return []
}

function normalizeItem(id, raw) {
  var value = raw || {}
  var aliases = normalizeAliases(value.aliases)
  var parent = value.parent
  if (parent === undefined)
    parent = id.indexOf(".") >= 0 ? id.split(".").slice(0, -1).join(".") : "root"
  if (id === "root") parent = ""

  var kind = value.action ? "action" : (value.target ? "link" : "menu")

  return {
    id: id,
    parent: parent,
    kind: kind,
    icon: value.icon || "",
    iconFont: value.iconFont || "",
    label: value.label || id,
    title: value.title || "",
    target: value.target || "",
    description: value.description || "",
    action: value.action || "",
    provider: value.provider || "",
    aliases: aliases,
    when: value.when || "",
    checked: value.checked || "",
    disabled: value.disabled || ""
  }
}

function parseMenuJsonc(raw) {
  var parsed = parseJsoncObject(raw)
  if (!parsed) return []

  var wrapped = parsed.items && typeof parsed.items === "object" && !Array.isArray(parsed.items)
  var source = wrapped ? parsed.items : parsed
  var out = []
  for (var id in source) {
    // Only the flat form needs the carve-out: an explicit items wrapper already
    // scopes the entries, so a row genuinely called "keybindings" still works
    // there. Without this, a keybindings block becomes an empty submenu on the
    // root menu, searchable and routable.
    if (!wrapped && RESERVED_TOP_LEVEL_KEYS.hasOwnProperty(id)) continue

    var entry = source[id]
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) continue
    out.push(normalizeItem(id, entry))
  }
  return out
}

function mergeMenuSources(defaultItems, userItems) {
  var nextItems = ({})
  var nextOrder = []
  var sources = [defaultItems || [], userItems || []]

  for (var s = 0; s < sources.length; s++) {
    var src = sources[s]
    for (var i = 0; i < src.length; i++) {
      var entry = src[i]
      if (!entry || !entry.id) continue
      if (!nextItems[entry.id]) nextOrder.push(entry.id)
      var prior = nextItems[entry.id] || {}
      var merged = {}
      for (var k in prior) merged[k] = prior[k]
      for (var k2 in entry) merged[k2] = entry[k2]
      merged.id = entry.id
      nextItems[entry.id] = merged
    }
  }

  if (!nextItems.root) {
    nextItems.root = { id: "root", parent: "", kind: "menu", icon: "", iconFont: "", label: "Go", title: "", target: "", description: "", aliases: [], when: "", checked: "", disabled: "", action: "", provider: "" }
    nextOrder.unshift("root")
  }
  for (var k3 = 0; k3 < nextOrder.length; k3++) nextItems[nextOrder[k3]].order = k3

  return {
    items: nextItems,
    itemOrder: nextOrder
  }
}

// Both merges below return fresh items/itemOrder objects for the caller to
// assign in one go. They must never write into the maps they are handed: those
// live in QML `var` properties, and an in-place write into such an object is
// occasionally dropped by the engine — the key lands with an undefined value.
// A lost write used to leave an id in itemOrder with no item behind it, and
// the next merge then kept that orphan and appended a second row for the same
// app, so the launcher listed it twice (and again on every later rescan).

// Swaps every app row for the current set. Rows keep the order they arrive in;
// ids already claimed (including duplicate desktop ids) are listed once.
function mergeAppRows(items, itemOrder, appRows) {
  var source = items || ({})
  var order = Array.isArray(itemOrder) ? itemOrder : []
  var rows = Array.isArray(appRows) ? appRows : []
  var nextItems = ({})
  var nextOrder = []

  for (var i = 0; i < order.length; i++) {
    var id = order[i]
    var existing = source[id]
    // Orphans (an id with no item) are dropped rather than carried forward,
    // so a single lost write cannot compound into a duplicate row.
    if (!existing || existing.kind === "app") continue
    nextItems[id] = existing
    nextOrder.push(id)
  }

  for (var j = 0; j < rows.length; j++) {
    var row = rows[j]
    if (!row || !row.id || nextItems[row.id]) continue
    row.order = nextOrder.length
    nextItems[row.id] = row
    nextOrder.push(row.id)
  }

  return { items: nextItems, itemOrder: nextOrder }
}

// Swaps the rows one provider contributed, leaving every other item untouched.
// Rows carry the id of the submenu that produced them, so a provider that runs
// again drops its previous batch — a plugin that was just enabled disappears
// from the Enable list — without disturbing static children declared in JSONC.
function swapProviderRows(items, itemOrder, menuId, rows) {
  var source = items || ({})
  var order = Array.isArray(itemOrder) ? itemOrder : []
  var incoming = Array.isArray(rows) ? rows : []
  var nextItems = ({})
  var nextOrder = []

  for (var i = 0; i < order.length; i++) {
    var id = order[i]
    var existing = source[id]
    if (!existing || existing.providerMenu === menuId) continue
    nextItems[id] = existing
    nextOrder.push(id)
  }

  for (var j = 0; j < incoming.length; j++) {
    var row = incoming[j]
    if (!row || !row.id || nextItems[row.id]) continue
    row.providerMenu = menuId
    row.order = nextOrder.length
    nextItems[row.id] = row
    nextOrder.push(row.id)
  }

  return { items: nextItems, itemOrder: nextOrder }
}

function item(items, id) {
  return items && items[id] ? items[id] : null
}

// Routes may name a real id (`system`, `setup.power`) or an alias declared in
// JSONC (`power-menu`, `settings`). An exact id beats any alias, and app rows
// are never routable: their aliases carry .desktop Keywords and GenericName
// for search, so an installed application could otherwise shadow a menu route
// (htop ships `Keywords=system;...`). Unknown strings fall through as the
// literal input so misspellings still attempt to open that id.
function resolveRoute(items, itemOrder, input) {
  var raw = String(input || "").toLowerCase().replace(/_/g, "-")
  if (!raw || raw === "go" || raw === "menu") return "root"
  if (item(items, raw)) return raw
  var order = Array.isArray(itemOrder) ? itemOrder : []
  for (var i = 0; i < order.length; i++) {
    var entry = item(items, order[i])
    if (!entry || entry.kind === "app" || !entry.aliases) continue
    for (var j = 0; j < entry.aliases.length; j++) {
      var alias = String(entry.aliases[j] || "").toLowerCase().replace(/_/g, "-")
      if (alias === raw) return entry.id
    }
  }
  return raw
}

function slugify(value) {
  return String(value || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "item"
}

function depthFor(items, id) {
  var depth = 0
  var current = item(items, id)
  var guard = 0

  while (current && current.parent && current.parent !== "root" && guard < 32) {
    depth += 1
    current = item(items, current.parent)
    guard += 1
  }

  return depth
}

function pathFor(items, id) {
  var labels = []
  var current = item(items, id)
  var guard = 0

  while (current && current.id !== "root" && guard < 32) {
    labels.unshift(current.label)
    current = item(items, current.parent)
    guard += 1
  }

  return labels.join(" › ")
}

function parentPathFor(items, id) {
  var entry = item(items, id)
  if (!entry || !entry.parent || entry.parent === "root") return ""
  return pathFor(items, entry.parent)
}

function isDescendantOf(items, id, ancestorId) {
  if (ancestorId === "root") return id !== "root"

  var current = item(items, id)
  var guard = 0
  while (current && current.parent && guard < 32) {
    if (current.parent === ancestorId) return true
    current = item(items, current.parent)
    guard += 1
  }

  return false
}

function childCount(items, itemOrder, id) {
  var count = 0
  var order = Array.isArray(itemOrder) ? itemOrder : []
  for (var i = 0; i < order.length; i++) {
    var entry = item(items, order[i])
    if (entry && entry.parent === id) count += 1
  }
  return count
}

function isVisible(items, itemOrder, whenResults, entry, depth) {
  if (!entry) return false
  if (entry.when && whenResults && whenResults[entry.id] === false) return false
  if (entry.kind !== "menu" && entry.kind !== "link") return true
  if (entry.provider) return true

  var guard = depth || 0
  if (guard >= 32) return false

  var target = entry.kind === "link" ? entry.target : entry.id
  var order = Array.isArray(itemOrder) ? itemOrder : []
  for (var i = 0; i < order.length; i++) {
    var child = item(items, order[i])
    if (child && child.parent === target && isVisible(items, itemOrder, whenResults, child, guard + 1)) return true
  }

  return false
}

// A `disabled:` row stays listed but goes dim and unselectable. The
// Install submenus use it so software already on the machine reads as
// installed rather than disappearing from the list it was installed from.
function isDisabled(disabledResults, entry) {
  if (!entry || !entry.disabled) return false
  return !!(disabledResults && disabledResults[entry.id])
}

// A disabled row is software you already have, which is the same thing the ✓
// says everywhere else in the menu, so it earns the same marker.
function labelFor(entry, checkedResults, disabledResults) {
  if (!entry) return ""
  var marked = (entry.checked && checkedResults && checkedResults[entry.id]) || isDisabled(disabledResults, entry)
  return marked ? entry.label + " ✓" : entry.label
}

function searchableToken(value) {
  return String(value || "").replace(/[._-]+/g, " ")
}

function leafIdFor(id) {
  var parts = String(id || "").split(".")
  return parts.length > 0 ? parts[parts.length - 1] : id
}

function nameSearchText(entry) {
  if (!entry) return ""
  var aliases = []
  var values = Array.isArray(entry.aliases) ? entry.aliases : []
  for (var i = 0; i < values.length; i++) aliases.push(searchableToken(values[i]))
  return [entry.label, searchableToken(leafIdFor(entry.id)), aliases.join(" ")].join(" ").toLowerCase()
}

function termInSearchWords(term, text) {
  var words = String(text || "").toLowerCase().split(/\s+/)
  for (var i = 0; i < words.length; i++) {
    if (words[i] === term) return true
  }
  return false
}

function descriptionTextMatches(query, text) {
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)
  for (var i = 0; i < terms.length; i++) {
    if (terms[i] && !termInSearchWords(terms[i], text)) return false
  }
  return true
}

function matchesQuery(entry, query, visible) {
  if (!entry || entry.id === "root") return false
  if (!visible) return false

  var nameText = nameSearchText(entry)
  var descriptionText = String(entry.description || "").toLowerCase()
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)

  for (var i = 0; i < terms.length; i++) {
    if (!terms[i]) continue
    if (nameText.indexOf(terms[i]) >= 0) continue
    if (termInSearchWords(terms[i], descriptionText)) continue
    return false
  }

  return true
}

function searchScore(items, entry, query) {
  var needle = String(query || "").toLowerCase().trim()
  var label = entry.label.toLowerCase()
  var nameText = nameSearchText(entry)
  var descriptionText = String(entry.description || "").toLowerCase()
  var score = 80

  if (label === needle) score = entry.parent === "root" ? 2 : 0
  // An installed app whose name contains the query as a whole word ("zen"
  // for Zen Browser) beats exact-labeled menu entries like Install > Zen.
  else if (entry.kind === "app" && label.split(/\s+/).indexOf(needle) >= 0) score = 0
  else if (label.indexOf(needle) === 0) score = 10
  else if (label.indexOf(needle) >= 0) score = 30
  else if (nameText.indexOf(needle) >= 0) score = 40
  else if (descriptionTextMatches(needle, descriptionText)) score = 60

  if (entry.kind === "menu" || entry.kind === "link") score -= 2
  // App rows sort after all menu items, so they lose the tiebreak below to an
  // equal match. Outrank those, but stay inside the tier so better ones win.
  if (entry.kind === "app") score -= 5

  return score * 1000 + depthFor(items, entry.id) * 25 + entry.order
}

function displayRow(items, itemOrder, checkedResults, disabledResults, entry, detail, score, section) {
  var target = entry.kind === "link" ? entry.target : entry.id
  return {
    itemId: entry.id,
    disabled: isDisabled(disabledResults, entry),
    kind: entry.kind,
    icon: entry.icon,
    iconFont: entry.iconFont || "",
    appIcon: entry.appIcon || "",
    appId: entry.appId || "",
    label: labelFor(entry, checkedResults, disabledResults),
    target: target,
    detail: detail || "",
    path: pathFor(items, entry.id),
    childCount: (entry.kind === "menu" || entry.kind === "link") ? childCount(items, itemOrder, target) : 0,
    action: entry.action || "",
    provider: entry.provider || "",
    score: score || 0,
    section: section || ""
  }
}

// Commands a `checked:` expression reads a value out of. Every sibling row
// asks the same one -- Defaults > Browser has seven rows all comparing
// against `omarchy-default-browser` -- so the batch runs it once and the rows
// read the captured answer.
//
// The capture has to be eager. These are read inside `$(...)`, and a value
// cached while one expression runs lives in that subshell only, so a lazy
// memo never survives to the expression after it.
var GUARD_READERS = [
  "omarchy-channel-current",
  "omarchy-default-agent",
  "omarchy-default-browser",
  "omarchy-default-editor",
  "omarchy-default-terminal",
  "omarchy-dns"
]

// Package and command presence account for most of what the guards ask, and
// asked one at a time they are almost all fork: the shipped menu spends over
// a second on them. Answer them inside the guard process instead. These
// shadow the real commands for the batch only, so they have to agree with
// them everywhere, including for no arguments at all (present is true of
// nothing, missing is not).
//
// `pacman -Q` resolves a name through what installed packages provide, not
// just what they are called -- with gvim installed it reports `vim` as
// present -- so the set has to carry provides too, or `install.editor.vim`
// comes back and offers to install what is already there. A version
// constraint (`bash>=1`) is not a name any set can answer, so it goes to
// pacman itself; no shipped guard writes one.
//
// `pacman -Qi` wraps a long list across continuation lines whenever COLUMNS
// is set in the environment, which a login shell may well have done, so the
// parser follows the indented lines rather than reading the first one and
// dropping half of what is installed.
function guardHelpers() {
  return 'declare -A __omarchy_pkgs=()\n'
    + 'mapfile -t __omarchy_pkg_names < <({ pacman -Qq; LC_ALL=C pacman -Qi'
    + " | awk '/^[A-Za-z]/ { provides = ($0 ~ /^Provides/); sub(/^[^:]*: /, \"\") }"
    + ' provides && $0 != "None" { n = split($0, p, " ");'
    + ' for (i = 1; i <= n; i++) { sub(/[<>=].*/, "", p[i]); print p[i] } }\'; } 2>/dev/null)\n'
    + 'for __omarchy_pkg in "${__omarchy_pkg_names[@]}"; do __omarchy_pkgs[$__omarchy_pkg]=1; done\n'
    + '__omarchy_pkg_has() { [[ -n ${__omarchy_pkgs[$1]-} ]] && return 0; '
    + '[[ $1 == *[\\<\\>=]* ]] && { pacman -Q "$1" &>/dev/null; return; }; return 1; }\n'
    + 'omarchy-pkg-present() { local p; for p in "$@"; do __omarchy_pkg_has "$p" || return 1; done; return 0; }\n'
    + 'omarchy-pkg-missing() { local p; for p in "$@"; do __omarchy_pkg_has "$p" || return 0; done; return 1; }\n'
    + 'omarchy-cmd-present() { local c; for c in "$@"; do command -v "$c" &>/dev/null || return 1; done; return 0; }\n'
    + 'omarchy-cmd-missing() { local c; for c in "$@"; do command -v "$c" &>/dev/null || return 0; done; return 1; }\n'
}

// Substitute the captured answer into the expression rather than shadowing
// the reader with a function. `$(reader)` and the variable holding what it
// printed are interchangeable -- both strip trailing newlines, both split the
// same way unquoted -- while a function would also catch `command -v reader`,
// `VAR=x reader`, and every other form, and answer those wrong. Anything but
// the plain substitution is left alone to run the real command.
function guardPrelude(guards) {
  var prelude = guardHelpers()

  for (var i = 0; i < GUARD_READERS.length; i++) {
    // The guards arrive already substituted, so what marks a reader as wanted
    // is the slot standing in for it, not the call it replaced.
    if (guards.indexOf(guardReaderSlot(i)) < 0) continue
    // `|| :` so a reader that exits nonzero cannot take the batch down with
    // it under a login shell that turned on errexit.
    prelude += "__omarchy_read_" + i + "=$(" + GUARD_READERS[i] + " 2>/dev/null) || :\n"
  }

  return prelude
}

function guardReaderSlot(index) {
  return "${__omarchy_read_" + index + "}"
}

function substituteGuardReaders(expression) {
  for (var i = 0; i < GUARD_READERS.length; i++)
    expression = expression.split("$(" + GUARD_READERS[i] + ")").join(guardReaderSlot(i))

  return expression
}

function guardLine(id, tag, expression) {
  return "if { " + substituteGuardReaders(expression) + "; } >/dev/null 2>&1; then echo "
    + id + ":" + tag + ":1; else echo " + id + ":" + tag + ":0; fi\n"
}

// One bash script for every `when:`, `checked:` and `disabled:` in the menu,
// reporting `<id>:<w|c|d>:<0|1>` per line. Speed is the whole point: the menu
// opens on the last evaluation's answers, so however long this takes is how
// long a row can contradict the state it describes.
function guardScript(items) {
  var guards = ""
  var ids = Object.keys(items || {})

  for (var i = 0; i < ids.length; i++) {
    var entry = items[ids[i]]
    if (!entry) continue
    if (entry.when) guards += guardLine(ids[i], "w", entry.when)
    if (entry.checked) guards += guardLine(ids[i], "c", entry.checked)
    if (entry.disabled) guards += guardLine(ids[i], "d", entry.disabled)
  }

  return guards ? guardPrelude(guards) + guards : ""
}

// --- keybindings -------------------------------------------------------

// The shipped bindings are the block in default/omarchy/omarchy-menu.jsonc.
// This is only the fallback for one that is missing or unparseable -- the same
// job builtinShellConfig does for shell.json in shell.qml.
var DEFAULT_KEYBINDINGS = {
  next: ["DOWN"],
  prev: ["UP"],
  pageNext: ["PAGEDOWN"],
  pagePrev: ["PAGEUP"],
  activate: ["RETURN", "ENTER", "RIGHT"],
  back: ["BACKSPACE", "LEFT"]
}

// Qt.Key_* values, spelled out because Node loads this file too and has no Qt.
// Names are the Qt.Key_ constants without the prefix, keyed lower-case so the
// lookup is case-insensitive. Letters, digits and punctuation typed as a single
// character resolve to themselves, so only the named keys need to be listed.
var KEY_NAME_MAP = {
  // navigation
  "up": 0x01000013, "down": 0x01000015, "left": 0x01000012, "right": 0x01000014,
  "pageup": 0x01000016, "pagedown": 0x01000017, "home": 0x01000010, "end": 0x01000011,
  // editing and activation
  "return": 0x01000004, "enter": 0x01000005, "escape": 0x01000000, "space": 0x20,
  "tab": 0x01000001, "backtab": 0x01000002, "backspace": 0x01000003, "delete": 0x01000007,
  "insert": 0x01000006, "print": 0x01000009,
  // function keys
  "f1": 0x01000030, "f2": 0x01000031, "f3": 0x01000032, "f4": 0x01000033,
  "f5": 0x01000034, "f6": 0x01000035, "f7": 0x01000036, "f8": 0x01000037,
  "f9": 0x01000038, "f10": 0x01000039, "f11": 0x0100003a, "f12": 0x0100003b,
  // every punctuation key Omarchy's own Hyprland bindings name: comma in five
  // bindings, SLASH in three, grave in two, PERIOD in one (plus the commented
  // example in config/hypr/bindings.lua); PRINT's four sit on the editing row
  "comma": 0x2c, "slash": 0x2f, "period": 0x2e, "grave": 0x60
}

// The Hyprland DSL's modifier words, the vocabulary config/hypr/bindings.lua and
// default/hypr/bindings/*.lua already write ("SUPER + SHIFT + R"), mapped onto
// Qt.KeyboardModifier flags. Keyed lower-case; the lookup folds case.
var MODIFIER_MAP = {
  "super": 0x10000000,
  "ctrl": 0x04000000,
  "alt": 0x08000000,
  "shift": 0x02000000
}

// One binding is one string in the Hyprland DSL: "CTRL + J". See docs/menu.md.
// Nothing half-resolved gets through: an unknown modifier fails the whole
// binding rather than dropping to the bare key, or "CTL + J" would leave a live
// binding on plain J -- taking the letter away from menu search, since the
// dispatch consults bindings before it treats a keystroke as typing.
function parseBinding(spec, action) {
  var text = String(spec === undefined || spec === null ? "" : spec).trim()
  if (!text) return null

  // The action is what a reader needs to find the offending line; the binding
  // alone does not say which entry it was under. Optional, so parseBinding
  // stays callable on its own.
  var where = action ? " for " + action : ""

  var parts = text.split("+")
  var key = resolveKeyName(parts.pop().trim())
  if (!key) {
    console.warn("menu keybindings: unknown key in " + JSON.stringify(spec) + where)
    return null
  }

  var modifiers = 0
  for (var i = 0; i < parts.length; i++) {
    var name = parts[i].trim().toLowerCase()
    if (!MODIFIER_MAP.hasOwnProperty(name)) {
      console.warn("menu keybindings: unknown modifier in " + JSON.stringify(spec) + where)
      return null
    }
    modifiers |= MODIFIER_MAP[name]
  }
  return { key: key, modifiers: modifiers }
}

// Key names are Qt's, folded to lower case for the lookup. A single character
// stands for itself, so only the named keys need a table entry.
function resolveKeyName(name) {
  var text = String(name === undefined || name === null ? "" : name)
  if (!text) return 0

  var lower = text.toLowerCase()
  if (KEY_NAME_MAP.hasOwnProperty(lower)) return KEY_NAME_MAP[lower]
  if (text.length === 1) return text.toUpperCase().charCodeAt(0)
  return 0
}

// Resolve a keybindings block into the {action: [{key, modifiers}]} form the
// dispatch matches against. An action listed with an empty array unbinds it, so
// a default can be dropped without replacing it; an action not listed at all
// keeps whatever the defaults bound.
//
// An action whose keys all fail to resolve is left out rather than emitted
// empty, so only a list written as [] reaches mergeKeybindings as an unbind. A
// typo costs you the key you misspelled, not the shipped ones it was joining.
function normalizeKeybindings(source) {
  if (!source || typeof source !== "object" || Array.isArray(source)) return null

  var out = {}
  for (var action in source) {
    var specs = source[action]
    if (!Array.isArray(specs)) continue

    var combos = []
    for (var i = 0; i < specs.length; i++) {
      var combo = parseBinding(specs[i], action)
      if (combo) combos.push(combo)
    }
    if (specs.length > 0 && combos.length === 0) continue
    out[action] = combos
  }
  return out
}

function parseMenuKeybindings(raw) {
  var parsed = parseJsoncObject(raw)
  if (!parsed) return null
  return normalizeKeybindings(parsed.keybindings)
}

// User keys are added to the shipped ones rather than replacing them, so
// binding CTRL + N to next does not cost you DOWN. Unbinding is therefore an
// explicit act: an action written as [] drops its keys entirely. Shipped keys
// come first, which only matters for the order bindingMatches reports a hit in.
function mergeKeybindings(defaults, user) {
  var out = {}
  var base = defaults || {}
  for (var action in base) out[action] = base[action]
  if (user) {
    for (var override in user) {
      var added = user[override]
      if (!added.length) out[override] = []
      else out[override] = (out[override] || []).concat(added)
    }
  }
  return out
}

// Qt.KeypadModifier, which Qt sets on every key the numeric keypad sends --
// Key_Enter is by definition the keypad's Return, so the shipped
// "ENTER" binding carries the bit on arrival and nothing else. It says
// where a key sits on the keyboard, not what the user held down, so it is
// cleared before comparing; leaving it in is what stopped keypad Enter and the
// keypad arrows from reaching the menu.
var IGNORED_MODIFIERS = 0x20000000

// Qt numbers every non-character key at or above this; below it a key value is
// the character's own code, which is why a single character resolves to itself.
var FIRST_NON_CHARACTER_KEY = 0x01000000

// An unmodified binding on a non-character key ignores what was held, because
// the hardcoded chain this replaced tested `event.key === Qt.Key_Down` with no
// modifier check at all: SHIFT + DOWN moved the selection, CTRL + RETURN
// activated. Keeping that is what makes the shipped defaults behave as they did.
//
// It is safe only there. A character key stays exact or CTRL + J would fire a
// bare J binding and take the letter from search, and a binding that names its
// own modifiers stays exact so CTRL + SHIFT + J never fires CTRL + J.
//
// One rule about the filter, and it belongs to back alone: an unmodified back
// binding steps aside while the search box has text, so LEFT moves through what
// you are typing instead of leaving the submenu, and a bare H bound to back
// types an h. Hold something -- CTRL + H -- and the binding stays live, because
// nobody types that into a search. The other actions keep working mid-search;
// navigating and activating a filtered list is the point of filtering it.
function bindingMatches(action, combos, event, filterHasText) {
  if (!combos || !event) return false

  var modifiers = event.modifiers & ~IGNORED_MODIFIERS
  for (var i = 0; i < combos.length; i++) {
    var combo = combos[i]
    if (action === "back" && filterHasText && combo.modifiers === 0) continue
    if (event.key !== combo.key) continue
    if (combo.modifiers === 0 && combo.key >= FIRST_NON_CHARACTER_KEY) return true
    if (modifiers === combo.modifiers) return true
  }
  return false
}

if (typeof module !== "undefined") {
  module.exports = {
    guardReaders: GUARD_READERS,
    guardScript: guardScript,
    stripJsonc: stripJsonc,
    parseBinding: parseBinding,
    parseJsoncObject: parseJsoncObject,
    normalizeAliases: normalizeAliases,
    normalizeItem: normalizeItem,
    parseMenuJsonc: parseMenuJsonc,
    mergeMenuSources: mergeMenuSources,
    mergeAppRows: mergeAppRows,
    swapProviderRows: swapProviderRows,
    item: item,
    resolveRoute: resolveRoute,
    slugify: slugify,
    depthFor: depthFor,
    pathFor: pathFor,
    parentPathFor: parentPathFor,
    isDescendantOf: isDescendantOf,
    childCount: childCount,
    isVisible: isVisible,
    isDisabled: isDisabled,
    labelFor: labelFor,
    searchableToken: searchableToken,
    leafIdFor: leafIdFor,
    nameSearchText: nameSearchText,
    termInSearchWords: termInSearchWords,
    descriptionTextMatches: descriptionTextMatches,
    matchesQuery: matchesQuery,
    searchScore: searchScore,
    displayRow: displayRow,
    defaultKeybindings: DEFAULT_KEYBINDINGS,
    normalizeKeybindings: normalizeKeybindings,
    parseMenuKeybindings: parseMenuKeybindings,
    mergeKeybindings: mergeKeybindings,
    bindingMatches: bindingMatches
  }
}
