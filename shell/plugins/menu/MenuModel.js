function stripJsonc(raw) {
  return String(raw || "")
    .replace(/^\s*\/\/[^\n]*(\n|$)/gm, "")
    .replace(/,(\s*[}\]])/g, "$1")
}

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
  var stripped = stripJsonc(raw)
  if (!stripped.trim()) return []

  var parsed
  try {
    parsed = JSON.parse(stripped)
  } catch (e) {
    return []
  }
  if (typeof parsed !== "object" || parsed === null) return []

  var source = (parsed.items && typeof parsed.items === "object" && !Array.isArray(parsed.items))
    ? parsed.items
    : parsed
  var out = []
  for (var id in source) {
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

// ------------------------------------------------------------- shortcuts
//
// `o.bind` writes ~/.local/state/omarchy/keybindings.tsv as it registers each
// binding, one `<keys>\t<command>` line per bind, because Hyprland reports Lua
// binds as dispatcher `__lua` and keeps the command to itself. A row earns its
// shortcut two ways: the binding runs the row's own `action`, or it opens the
// row by route — the `omarchy menu toggle theme` that Style > Theme answers to.
var MENU_ROUTE_PATTERN = /^omarchy(?:-menu|\s+menu)\s+(?:toggle|summon)\s+(\S+)$/

// A `code:34` key names an XKB keycode, not anything a reader could press, and
// resolving one costs a keymap compile the open path will not pay.
function keysArePressable(keys) {
  return keys.indexOf("code:") < 0 && keys.indexOf("mouse:") < 0
}

function menuRouteFor(command) {
  var match = MENU_ROUTE_PATTERN.exec(command)
  return match ? match[1] : ""
}

// Keys as authored ("SUPER + SHIFT + CTRL + SPACE") are four times as wide as
// the label they sit beside. Modifiers become their symbols, which the menu has
// room for; the key itself stays spelled out so the row still reads as a key to
// press. Media keys drop the XF86 vendor prefix nobody has printed on a keycap.
var MODIFIER_SYMBOLS = ({
  SUPER: "⌘",
  SHIFT: "⇧",
  CTRL: "⌃",
  CONTROL: "⌃",
  ALT: "⌥"
})

function shortcutLabel(keys) {
  var parts = String(keys || "").split("+")
  var modifiers = ""
  var key = ""

  for (var i = 0; i < parts.length; i++) {
    var part = parts[i].trim().toUpperCase()
    if (!part) continue
    if (MODIFIER_SYMBOLS[part]) modifiers += MODIFIER_SYMBOLS[part]
    else key = part.indexOf("XF86") === 0 ? part.slice(4) : part
  }

  return modifiers && key ? modifiers + " " + key : modifiers + key
}

function parseKeybindings(raw) {
  var byCommand = ({})
  var byRoute = ({})
  var lines = String(raw || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    var tab = lines[i].indexOf("\t")
    if (tab < 0) continue
    // Split on the first tab only: a command may well contain one of its own.
    var keys = lines[i].substring(0, tab).trim()
    var command = lines[i].substring(tab + 1).trim()
    if (!keys || !command || !keysArePressable(keys)) continue

    var label = shortcutLabel(keys)
    // First binding wins, so a user file that adds a second key for a command
    // reads as an alternative rather than a replacement.
    if (!byCommand[command]) byCommand[command] = label
    var route = menuRouteFor(command)
    if (route && !byRoute[route]) byRoute[route] = label
  }

  return { byCommand: byCommand, byRoute: byRoute }
}

// An app row and a binding reach the same application by different routes: the
// row runs the desktop entry's Exec, the binding runs whatever `o.bind` was
// handed. Both reduce to the same key.
//
// Omarchy's launchers are the rest of the distance, and they say what they open
// rather than being guessed at: `# omarchy:launches=` in the launcher itself,
// collected into `targets` (see Menu.qml). A launcher that declares nothing
// matches nothing, because a name is not evidence — `omarchy-launch-signal`
// runs signal-desktop, and `omarchy-launch-browser` runs whichever browser is
// currently the default. The `-or-focus` wrappers take a window pattern first
// and delegate the rest, so they unwrap to what they delegate to.
var SESSION_WRAPPERS = ["setsid", "uwsm-app", "systemd-cat"]
var LAUNCHER_PREFIX = "omarchy-launch-"

function commandTokens(command) {
  if (Array.isArray(command)) return command.slice()

  var tokens = []
  var pattern = /'([^']*)'|"([^"]*)"|(\S+)/g
  var match

  while ((match = pattern.exec(String(command || "")))) {
    if (match[1] !== undefined) tokens.push(match[1])
    else if (match[2] !== undefined) tokens.push(match[2])
    else tokens.push(match[3])
  }

  return tokens
}

// Two keys come back: the whole command, and the program on its own. Only a
// binding that runs a bare program is allowed to match on the program — it then
// claims the app that is that program whatever arguments the desktop entry adds
// (`spotify --uri=%u`). A binding carrying arguments of its own has to match in
// full, so `omarchy-launch-browser --private` never claims the browser that the
// plain binding does.
function launchKeys(command, targets, depth) {
  var tokens = commandTokens(command)
  var stripped = false

  if (tokens[0] === "uwsm" && tokens[1] === "app") { tokens = tokens.slice(2); stripped = true }
  while (tokens.length && (tokens[0] === "--" || SESSION_WRAPPERS.indexOf(tokens[0]) >= 0)) {
    tokens = tokens.slice(1)
    stripped = true
  }
  // `setsid -f chromium` runs chromium, not -f.
  while (stripped && tokens.length && tokens[0].charAt(0) === "-") tokens = tokens.slice(1)
  if (!tokens.length) return { command: "", program: "", bare: false }

  // Bounded: a launcher that resolves to another launcher cannot loop forever.
  var next = (depth || 0) + 1
  if (next > 4) return { command: "", program: "", bare: false }

  if (tokens[0] === LAUNCHER_PREFIX + "or-focus" && tokens.length > 1) return launchKeys(tokens[tokens.length - 1], targets, next)
  if (tokens[0] === LAUNCHER_PREFIX + "or-focus-webapp") tokens = [LAUNCHER_PREFIX + "webapp"].concat(tokens.slice(2))

  var program = String(tokens[0] || "").replace(/^.*\//, "")

  if (tokens.length === 1 && targets && targets[program]) return launchKeys(targets[program], targets, next)

  // A desktop entry and a binding disagree over a trailing slash on the same
  // URL often enough that it cannot be what separates them.
  tokens[0] = program
  var whole = tokens.map(function(token) { return String(token).replace(/\/+$/, "") }).join(" ")

  return { command: whole, program: program, bare: tokens.length === 1 }
}

// Several apps can run one program: every Chrome web app runs the browser with
// arguments after it. Only one of them is that program, and it is the one that
// runs it plainly — so a bare entry owns the name, an argument-carrying entry
// owns it only when it is the sole claimant, and a name several entries claim
// alike belongs to none of them. Spotify keeps its key off `spotify --uri=%u`;
// `chromium --app=...` does not inherit the browser's.
function programOwner(program) {
  if (!program) return ""
  if (program.bare === 1) return program.bareId
  return program.bare === 0 && program.count === 1 ? program.id : ""
}

// id → shortcut label, resolved once per (re)load instead of per row. Routes go
// through the same alias resolution `omarchy menu summon` uses, so a binding on
// `theme` finds `style.theme`. An action match wins: it names one row, while a
// route names whatever currently answers to that name.
function resolveShortcuts(items, itemOrder, shortcuts, targets) {
  var byId = ({})
  if (!shortcuts) return byId

  var byLaunch = ({})
  var byProgram = ({})
  for (var command in shortcuts.byCommand) {
    var launch = launchKeys(command, targets)
    if (launch.command && !byLaunch[launch.command]) byLaunch[launch.command] = shortcuts.byCommand[command]
    if (launch.bare && !byProgram[launch.program]) byProgram[launch.program] = shortcuts.byCommand[command]
  }

  // Several apps can run one program: every Chrome web app runs the browser
  // with arguments. Only one of them is that program, and it is the one running
  // it plainly, so a bare entry owns the name outright and an argument-carrying
  // entry owns it only when nothing else claims it — which is how Spotify keeps
  // its key while `chromium --app=...` does not inherit the browser's.
  var order = Array.isArray(itemOrder) ? itemOrder : []
  var launches = ({})
  var programs = ({})

  for (var i = 0; i < order.length; i++) {
    var entry = item(items, order[i])
    if (!entry || !entry.exec) continue

    var launch = launches[entry.id] = launchKeys(entry.exec, targets)
    if (!launch.program) continue

    var program = programs[launch.program] || (programs[launch.program] = { bare: 0, bareId: "", count: 0, id: "" })
    program.count += 1
    program.id = entry.id
    if (launch.bare) { program.bare += 1; program.bareId = entry.id }
  }

  for (var j = 0; j < order.length; j++) {
    var row = item(items, order[j])
    if (!row) continue

    var keys = row.action ? shortcuts.byCommand[row.action] : ""
    var rowLaunch = launches[row.id]
    if (!keys && rowLaunch) keys = byLaunch[rowLaunch.command] || (programOwner(programs[rowLaunch.program]) === row.id ? byProgram[rowLaunch.program] : "") || ""
    if (keys) byId[row.id] = keys
  }

  for (var route in shortcuts.byRoute) {
    var id = resolveRoute(items, itemOrder, route)
    if (item(items, id) && !byId[id]) byId[id] = shortcuts.byRoute[route]
  }

  return byId
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

function displayRow(items, itemOrder, checkedResults, disabledResults, shortcutsById, entry, detail, score, section) {
  var target = entry.kind === "link" ? entry.target : entry.id
  return {
    itemId: entry.id,
    disabled: isDisabled(disabledResults, entry),
    shortcut: (shortcutsById && shortcutsById[entry.id]) || "",
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

if (typeof module !== "undefined") {
  module.exports = {
    guardReaders: GUARD_READERS,
    guardScript: guardScript,
    stripJsonc: stripJsonc,
    normalizeAliases: normalizeAliases,
    normalizeItem: normalizeItem,
    parseMenuJsonc: parseMenuJsonc,
    mergeMenuSources: mergeMenuSources,
    mergeAppRows: mergeAppRows,
    swapProviderRows: swapProviderRows,
    item: item,
    resolveRoute: resolveRoute,
    parseKeybindings: parseKeybindings,
    shortcutLabel: shortcutLabel,
    launchKeys: launchKeys,
    resolveShortcuts: resolveShortcuts,
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
    displayRow: displayRow
  }
}
