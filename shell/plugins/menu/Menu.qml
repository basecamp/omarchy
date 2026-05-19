import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons

Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  // Plugin lifecycle hooks. The host calls open(payloadJson) after
  // `omarchy-shell shell summon omarchy.menu ...` and close() when hidden.
  property string pendingInitialMenu: "root"

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    if (payload.fontFamily) root.fontFamily = payload.fontFamily

    if (payload.mode === "select" || payload.mode === "input") {
      root.openDmenu(payload)
    } else {
      root.pendingInitialMenu = payload.initialMenu || payload.menu || "root"
      root.openExistingMenu(root.pendingInitialMenu)
    }
  }

  function close() {
    root.cancel()
  }

  property string fontFamily: Quickshell.env("OMARCHY_MENU_FONT") || "monospace"
  // JSONC menu definitions. The shell parses both at startup and merges
  // the user file on top of the defaults, so the keybind → IPC → visible
  // path doesn't have to shell out to bash + jq on every open.
  property string defaultMenuPath: omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
  property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
  property var defaultMenuItems: []
  property var userMenuItems: []
  property bool opened: false
  property string mode: "menu"
  readonly property bool dmenuActive: mode === "select" || mode === "input"
  property string dmenuPrompt: ""
  property var dmenuOptions: []
  property string selectionFile: ""
  property string doneFile: ""
  property int dmenuWidth: 300
  property int dmenuMaxHeight: 0
  property bool requestActive: false
  property bool rowsLoaded: false
  property string activeMenu: "root"
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property int requestSerial: 0
  property int applySerial: 0
  property var items: ({})
  property var itemOrder: []
  property var navStack: []
  property var providersLoaded: ({})
  property var providerQueue: []
  // Bound to the central [menu] section in shell.toml via Color.qml.
  // Each color already includes its alpha companion (composed in the
  // singleton), so consumers can drop them straight into a Rectangle.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color selectedBorder: Color.menu.selectedBorder
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int baseRowHeight: Math.max(Style.space(50), Style.font.body + Style.spacing.rowPaddingX * 2)
  property int detailRowHeight: Math.max(Style.space(58), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  property int rowSpacing: Style.spacing.xs
  property int dividerHeight: Style.space(17)
  property bool searchDivider: false
  property int layoutSerial: 0
  property int cardWidth: Math.min(root.dmenuActive ? Style.space(root.dmenuWidth) : ((root.activeMenu === "trigger.capture.screenrecord" || root.activeMenu === "style.font") ? Style.space(520) : Style.space(300)), panel.width - Style.gapsOut * 2)
  property int visibleRowsHeight: root.dmenuActive ? dmenuRowListHeight(layoutSerial, displayModel.count, filterText) : rowListHeight(layoutSerial, displayModel.count, filterText, searchDivider)
  property int cardHeight: root.dmenuActive
    ? Math.min(contentMargin * 2 + headerHeight + (mode === "input" ? 0 : contentSpacing + visibleRowsHeight), panel.height - Style.gapsOut * 2)
    : Math.min(Math.max(Style.space(220), contentMargin * 2 + headerHeight + contentSpacing + visibleRowsHeight), panel.height - Style.gapsOut * 2)

  function withAlpha(color, alpha) {
    return Qt.rgba(color.r, color.g, color.b, alpha)
  }

  function shellQuote(value) {
    return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
  }

  function finishRequest(selection) {
    if (!root.requestActive || !root.doneFile) {
      root.opened = false
      return
    }

    var activeSelectionFile = root.selectionFile
    var activeDoneFile = root.doneFile
    root.requestActive = false
    root.selectionFile = ""
    root.doneFile = ""

    if (selection === null || selection === undefined) {
      resultProc.command = ["bash", "-lc", ": > " + root.shellQuote(activeDoneFile)]
    } else {
      resultProc.command = ["bash", "-lc", "printf '%s\\n' " + root.shellQuote(selection) + " > " + root.shellQuote(activeSelectionFile) + "; : > " + root.shellQuote(activeDoneFile)]
    }
    resultProc.running = true
  }

  function rowHeightForDetail(detail) {
    return root.filterText && detail ? root.detailRowHeight : root.baseRowHeight
  }

  function rowListHeight(_serial, _count, _filter, _divider) {
    if (displayModel.count === 0) return root.baseRowHeight

    var count = Math.min(displayModel.count, 10)
    var total = 0
    var previousSection = ""

    for (var i = 0; i < count; i++) {
      var row = displayModel.get(i)
      if (i > 0) total += root.rowSpacing
      if (row.section === "drilldown" && previousSection !== "drilldown") total += root.dividerHeight
      total += root.rowHeightForDetail(row.detail)
      previousSection = row.section
    }

    return total
  }

  function dmenuRowListHeight(_serial, _count, _filter) {
    if (root.mode === "input") return 0
    if (displayModel.count === 0) return root.baseRowHeight

    var count = Math.min(displayModel.count, 10)
    var total = 0
    for (var i = 0; i < count; i++) {
      if (i > 0) total += root.rowSpacing
      total += root.baseRowHeight
    }

    return root.dmenuMaxHeight > 0 ? Math.min(total, Style.space(root.dmenuMaxHeight)) : total
  }

  function item(id) {
    return root.items[id] || null
  }

  // ------------------------------------------------------------------
  // JSONC → normalized item array. Mirrors the bash bin's jq pipeline so
  // the on-disk authoring format stays untouched.
  // ------------------------------------------------------------------

  function stripJsonc(raw) {
    // Match what the bash bin's jq pipeline accepts: full-line `//` comments
    // plus trailing commas before } or ]. Anything fancier should land in
    // valid JSON anyway.
    return String(raw || "")
      .replace(/^\s*\/\/[^\n]*(\n|$)/gm, "")
      .replace(/,(\s*[}\]])/g, "$1")
  }

  function normalizeAliases(value) {
    if (Array.isArray(value)) return value.filter(function(v) { return v })
    if (typeof value === "string" && value) return [value]
    return []
  }

  function normalizeKeywords(id, aliases, raw) {
    function space(s) { return String(s || "").replace(/[._-]+/g, " ") }
    var parts = [space(id), aliases.map(space).join(" "), raw || ""].join(" ").split(/\s+/)
    var seen = {}
    var out = []
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i]
      if (!p || seen[p]) continue
      seen[p] = true
      out.push(p)
    }
    return out.join(" ")
  }

  function normalizeItem(id, raw) {
    var aliases = normalizeAliases(raw.aliases)
    var parent = raw.parent
    if (parent === undefined) {
      parent = id.indexOf(".") >= 0 ? id.split(".").slice(0, -1).join(".") : "root"
    }
    if (id === "root") parent = ""

    var kind = raw.action ? "action" : (raw.target ? "link" : "menu")

    return {
      id: id,
      parent: parent,
      kind: kind,
      icon: raw.icon || "",
      label: raw.label || id,
      target: raw.target || "",
      keywords: normalizeKeywords(id, aliases, raw.keywords),
      description: raw.description || "",
      action: raw.action || "",
      provider: raw.provider || "",
      aliases: aliases,
      when: raw.when || "",
      checked: raw.checked || ""
    }
  }

  function parseMenuJsonc(raw) {
    var stripped = stripJsonc(raw)
    if (!stripped.trim()) return []
    var parsed
    try { parsed = JSON.parse(stripped) } catch (e) {
      console.warn("omarchy-menu: JSONC parse failed:", e)
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

  // Merge defaults + user extension. Later entries override earlier ones
  // on a per-key basis (so the user can tweak label/icon/action without
  // re-declaring the whole row).
  function rebuildItemsFromSources() {
    var nextItems = ({})
    var nextOrder = []
    var sources = [root.defaultMenuItems || [], root.userMenuItems || []]
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
      nextItems.root = { id: "root", parent: "", kind: "menu", icon: "", label: "Go", target: "", keywords: "", description: "", aliases: [], when: "", checked: "", action: "", provider: "" }
      nextOrder.unshift("root")
    }
    for (var k3 = 0; k3 < nextOrder.length; k3++) nextItems[nextOrder[k3]].order = k3
    root.items = nextItems
    root.itemOrder = nextOrder
    root.rowsLoaded = true
    root.evaluateGuards()
    if (root.opened) root.rebuildDisplay()
  }

  // Each known provider is a tiny bash one-liner that enumerates a list and
  // emits one tab-delimited row per item: `label\tvalue\tcurrent`. The shell
  // turns those into menu items children of `menuId`.
  readonly property var providers: ({
    "fonts": {
      script: "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
      icon: "",
      actionFor: function(value) { return "omarchy-font-set '" + value.replace(/'/g, "'\\''") + "'" },
      keywordsFor: function(value) { return value + " typeface" }
    },
    "power-profiles": {
      script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
      icon: "\udb81\udc0b",
      actionFor: function(value) { return "powerprofilesctl set '" + value.replace(/'/g, "'\\''") + "'" },
      keywordsFor: function(value) { return value + " power profile" }
    }
  })

  function slugify(value) {
    return String(value || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "item"
  }

  function startProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return
    var spec = root.providers[entry.provider]
    if (!spec) return

    root.providersLoaded[id] = true
    providerProc.menuId = id
    providerProc.providerKey = entry.provider
    providerProc.collected = ""
    providerProc.command = ["bash", "-lc", spec.script]
    providerProc.running = true
  }

  function mergeProviderRows(rows, menuId, providerKey) {
    var spec = root.providers[providerKey]
    if (!spec) return
    var changed = false
    var lines = String(rows || "").split("\n")
    var nextOrder = root.itemOrder.slice()
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var parts = line.split("\t")
      var label = parts[0] || ""
      var value = parts[1] || parts[0] || ""
      var current = parts[2] || ""
      if (!label) continue
      var id = menuId + "." + root.slugify(value)
      if (!root.items[id]) nextOrder.push(id)
      root.items[id] = {
        id: id,
        parent: menuId,
        kind: "action",
        icon: (value === current) ? "✓" : (spec.icon || ""),
        label: label,
        target: "",
        keywords: spec.keywordsFor(value),
        description: "",
        action: spec.actionFor(value),
        provider: "",
        aliases: [],
        when: "",
        checked: "",
        order: nextOrder.indexOf(id)
      }
      changed = true
    }
    root.itemOrder = nextOrder
    if (changed && root.opened) root.rebuildDisplay()
  }

  function startNextProvider() {
    if (providerProc.running) return

    while (root.providerQueue.length > 0) {
      var id = root.providerQueue.shift()
      var entry = root.item(id)
      if (!entry || !entry.provider || root.providersLoaded[id]) continue

      root.startProviderForMenu(id)
      return
    }
  }

  function loadProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return

    if (providerProc.running) {
      if (root.providerQueue.indexOf(id) < 0) root.providerQueue = root.providerQueue.concat([id])
      return
    }

    root.startProviderForMenu(id)
  }

  function loadProvidersForSearch() {
    var active = root.item(root.activeMenu) ? root.activeMenu : "root"

    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (!entry || !entry.provider || root.providersLoaded[entry.id]) continue
      if (active !== "root" && entry.id !== active && !root.isDescendantOf(entry.id, active)) continue

      root.loadProviderForMenu(entry.id)
    }
  }

  function depthFor(id) {
    var depth = 0
    var current = root.item(id)
    var guard = 0

    while (current && current.parent && current.parent !== "root" && guard < 32) {
      depth += 1
      current = root.item(current.parent)
      guard += 1
    }

    return depth
  }

  function pathFor(id) {
    var labels = []
    var current = root.item(id)
    var guard = 0

    while (current && current.id !== "root" && guard < 32) {
      labels.unshift(current.label)
      current = root.item(current.parent)
      guard += 1
    }

    return labels.join(" › ")
  }

  function parentPathFor(id) {
    var entry = root.item(id)
    if (!entry || !entry.parent || entry.parent === "root") return ""

    return root.pathFor(entry.parent)
  }

  function breadcrumbFor(id) {
    var path = root.pathFor(id)
    return path ? ("Go › " + path) : "Go"
  }

  function isDescendantOf(id, ancestorId) {
    if (ancestorId === "root") return id !== "root"

    var current = root.item(id)
    var guard = 0
    while (current && current.parent && guard < 32) {
      if (current.parent === ancestorId) return true
      current = root.item(current.parent)
      guard += 1
    }

    return false
  }

  function childCount(id) {
    var count = 0
    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (entry && entry.parent === id) count += 1
    }

    return count
  }

  // Items whose `when:` evaluated to false are hidden everywhere — nav,
  // drilldown, and search. Items with no `when:` are always visible.
  function isVisible(entry) {
    if (!entry) return false
    if (!entry.when) return true
    var result = root.whenResults[entry.id]
    return result === undefined ? true : result
  }

  // Label with the ✓ marker baked in when `checked:` evaluated truthy.
  function labelFor(entry) {
    if (!entry) return ""
    if (entry.checked && root.checkedResults[entry.id]) return entry.label + " ✓"
    return entry.label
  }

  function matchesQuery(entry, query) {
    if (!entry || entry.id === "root") return false
    if (!root.isVisible(entry)) return false

    var haystack = (entry.label + " " + root.pathFor(entry.id) + " " + entry.keywords + " " + entry.description).toLowerCase()
    var terms = query.toLowerCase().trim().split(/\s+/)

    for (var i = 0; i < terms.length; i++) {
      if (terms[i] && haystack.indexOf(terms[i]) === -1) return false
    }

    return true
  }

  function searchScore(entry, query) {
    var needle = query.toLowerCase().trim()
    var label = entry.label.toLowerCase()
    var path = root.pathFor(entry.id).toLowerCase()
    var keywords = entry.keywords.toLowerCase()
    var parent = root.item(entry.parent)
    var parentLabel = parent ? parent.label.toLowerCase() : ""
    var score = 80

    if (label === needle) score = entry.parent === "root" ? 2 : 0
    else if (label.indexOf(needle) === 0) score = 10
    else if (path.indexOf(needle) === 0) score = entry.kind === "action" ? 12 : 14
    else if (parentLabel === needle) score = entry.kind === "action" ? 18 : 20
    else if (label.indexOf(needle) >= 0) score = 30
    else if (path.indexOf(needle) >= 0) score = 40
    else if (keywords.indexOf(needle) >= 0) score = 50

    if (entry.kind === "menu" || entry.kind === "link") score -= 2

    return score * 1000 + root.depthFor(entry.id) * 25 + entry.order
  }

  function displayRow(entry, detail, score, section) {
    var target = entry.kind === "link" ? entry.target : entry.id
    return {
      itemId: entry.id,
      kind: entry.kind,
      icon: entry.icon,
      label: root.labelFor(entry),
      target: target,
      detail: detail || "",
      path: root.pathFor(entry.id),
      childCount: (entry.kind === "menu" || entry.kind === "link") ? root.childCount(target) : 0,
      action: entry.action || "",
      provider: entry.provider || "",
      score: score || 0,
      section: section || ""
    }
  }

  function rebuildDmenuDisplay() {
    displayModel.clear()
    root.searchDivider = false

    if (root.mode === "input") {
      layoutSerial += 1
      return
    }

    var query = root.filterText.trim().toLowerCase()
    for (var i = 0; i < root.dmenuOptions.length; i++) {
      var label = String(root.dmenuOptions[i] || "")
      if (query && label.toLowerCase().indexOf(query) < 0) continue
      displayModel.append({
        itemId: "dmenu." + i,
        kind: "dmenu",
        icon: "",
        label: label,
        target: "",
        detail: "",
        path: "",
        childCount: 0,
        action: "",
        provider: "",
        score: i,
        section: ""
      })
    }

    layoutSerial += 1

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function rebuildDisplay() {
    if (root.dmenuActive) {
      root.rebuildDmenuDisplay()
      return
    }

    displayModel.clear()

    if (!root.rowsLoaded) return

    var active = root.item(root.activeMenu) ? root.activeMenu : "root"
    root.activeMenu = active
    var rows = []
    var query = root.filterText.trim()
    root.searchDivider = false

    if (query) {
      var currentRows = []
      var drilldownRows = []

      for (var i = 0; i < root.itemOrder.length; i++) {
        var entry = root.item(root.itemOrder[i])
        if (!entry || entry.id === "root") continue
        if (!root.isDescendantOf(entry.id, active)) continue
        if (!root.matchesQuery(entry, query)) continue

        var detail = root.parentPathFor(entry.id)
        var row = root.displayRow(entry, detail, root.searchScore(entry, query))
        if (entry.parent === active) currentRows.push(row)
        else drilldownRows.push(row)
      }

      var searchSort = function(a, b) {
        if (a.score !== b.score) return a.score - b.score
        return a.path.localeCompare(b.path)
      }

      currentRows.sort(searchSort)
      drilldownRows.sort(searchSort)
      root.searchDivider = currentRows.length > 0 && drilldownRows.length > 0
      if (root.searchDivider) {
        for (var d = 0; d < drilldownRows.length; d++) drilldownRows[d].section = "drilldown"
      }
      rows = currentRows.concat(drilldownRows)
    } else {
      if (active !== "root") {
        var parentTarget = root.item(active).parent || "root"
        var backTarget = root.navStack.length > 0 ? root.navStack[root.navStack.length - 1] : parentTarget
        rows.push({ itemId: "__back", kind: "back", icon: "", label: "Back", target: backTarget, detail: root.breadcrumbFor(backTarget), path: "", childCount: 0, action: "", score: -1, section: "" })
      }

      for (var j = 0; j < root.itemOrder.length; j++) {
        var child = root.item(root.itemOrder[j])
        if (!child || child.parent !== active) continue
        if (!root.isVisible(child)) continue
        rows.push(root.displayRow(child, child.description, child.order))
      }
    }

    for (var k = 0; k < rows.length; k++) displayModel.append(rows[k])
    layoutSerial += 1

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function select(delta) {
    if (displayModel.count === 0) return

    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = false
    if (!root.dmenuActive && root.filterText.trim()) root.loadProvidersForSearch()
    root.rebuildDisplay()
  }

  function setActiveMenu(id, pushHistory) {
    if (!root.item(id)) id = "root"
    if (pushHistory && id !== root.activeMenu) root.navStack = root.navStack.concat([root.activeMenu])
    root.activeMenu = id
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = false
    root.rebuildDisplay()
    root.loadProviderForMenu(id)
  }

  function goBack() {
    if (root.activeMenu === "root") return false

    if (root.navStack.length > 0) {
      var previous = root.navStack[root.navStack.length - 1]
      root.navStack = root.navStack.slice(0, root.navStack.length - 1)
      root.setActiveMenu(previous, false)
      return true
    }

    var active = root.item(root.activeMenu)
    root.setActiveMenu((active && active.parent) ? active.parent : "root", false)
    return true
  }

  function activateIndex(index) {
    if (root.dmenuActive) {
      if (root.mode === "input") {
        root.applyDmenuSelection(root.filterText)
        return
      }
      if (index < 0 || index >= displayModel.count) return
      root.applyDmenuSelection(displayModel.get(index).label)
      return
    }

    if (index < 0 || index >= displayModel.count) return

    var row = displayModel.get(index)
    if (row.kind === "back") {
      root.goBack()
    } else if (row.kind === "menu" || row.kind === "link") {
      root.setActiveMenu(row.target || row.itemId, true)
    } else {
      root.applySelected(row.itemId, row.action)
    }
  }

  function applyDmenuSelection(value) {
    applySerial = requestSerial
    opened = false
    filterText = ""
    root.finishRequest(value)
  }

  function applySelected(id, action) {
    if (!id) { cancel(); return }
    applySerial = requestSerial
    opened = false
    filterText = ""
    if (action) Quickshell.execDetached(["bash", "-lc", action])
  }

  function cancel() {
    if (root.dmenuActive) root.finishRequest(null)
    opened = false
    filterText = ""
  }

  function openExistingMenu(initialMenu) {
    requestSerial += 1
    mode = "menu"
    requestActive = false
    selectionFile = ""
    doneFile = ""
    activeMenu = root.item(initialMenu) ? initialMenu : "root"
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = false
    root.evaluateGuards()
    opened = true
    rebuildDisplay()
    loadProviderForMenu(activeMenu)

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function openDmenu(payload) {
    requestSerial += 1
    mode = payload.mode === "input" ? "input" : "select"
    dmenuPrompt = String(payload.prompt || (mode === "input" ? "Input" : "Select"))
    dmenuOptions = Array.isArray(payload.options) ? payload.options : []
    selectionFile = String(payload.selectionFile || "")
    doneFile = String(payload.doneFile || "")
    requestActive = !!doneFile
    dmenuWidth = Math.max(1, Number(payload.width || 300))
    dmenuMaxHeight = Math.max(0, Number(payload.maxHeight || 0))
    activeMenu = "root"
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = false
    opened = true
    rebuildDisplay()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  ListModel { id: displayModel }

  // ----------------------------------------------------------- IPC surface
  //
  // `omarchy-shell menu summon <id>` is the keybind hot path — the
  // Hyprland bindings call straight into here, no bash hops. `refresh` is
  // a manual nudge for when watchChanges isn't enough (e.g. someone wired
  // a CI step that re-emits the JSONC).

  // Mirrors `route_target` in the old bash bin: caller may pass a real id
  // (`system`, `setup.power`) or an alias declared in JSONC (`power`,
  // `reminder-set`). Unknown strings fall through to the id-as-route
  // behavior so misspellings still attempt to open the literal id.
  function resolveRoute(input) {
    var raw = String(input || "").toLowerCase().replace(/_/g, "-")
    if (!raw || raw === "go" || raw === "menu") return "root"
    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.items[root.itemOrder[i]]
      if (!entry || !entry.aliases) continue
      for (var j = 0; j < entry.aliases.length; j++) {
        var alias = String(entry.aliases[j] || "").toLowerCase().replace(/_/g, "-")
        if (alias === raw) return entry.id
      }
    }
    return raw
  }

  IpcHandler {
    target: "menu"

    function summon(initialMenu: string): string {
      var id = root.resolveRoute(initialMenu)
      var entry = root.items[id]
      // If the resolved id is an action (i.e. the user invoked an alias for
      // a leaf, e.g. `omarchy-shell menu summon screenrecord-stop`),
      // run it directly instead of opening an action with no children.
      if (entry && entry.kind === "action" && entry.action) {
        Quickshell.execDetached(["bash", "-lc", entry.action])
        return "ok"
      }
      // If it's a link (a redirect to another menu), follow the link.
      if (entry && entry.kind === "link" && entry.target) id = entry.target
      var payload = JSON.stringify({ menu: id })
      root.open(payload)
      return "ok"
    }

    // Hitting the same menu keybind while the menu is already visible should
    // close it — even if the requested target differs from the active one.
    // Matches the old bash bin's `close_visible_quickshell_menu` short-circuit.
    function toggle(initialMenu: string): string {
      if (root.opened) {
        root.cancel()
        return "closed"
      }
      return summon(initialMenu)
    }

    function refresh(): string {
      defaultMenuFile.reload()
      userMenuFile.reload()
      return "ok"
    }

    function close(): string {
      root.cancel()
      return "ok"
    }

    function ping(): string { return "ok" }
  }

  Process {
    id: providerProc
    property string menuId: ""
    property string providerKey: ""
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { providerProc.collected += data + "\n" }
    }
    onExited: {
      root.mergeProviderRows(providerProc.collected, providerProc.menuId, providerProc.providerKey)
      if (root.filterText.trim()) root.loadProvidersForSearch()
      root.startNextProvider()
    }
  }

  Process {
    id: resultProc
    onExited: {
      if (root.applySerial === root.requestSerial)
        root.opened = false
    }
  }

  // The JSONC sources are watched so live edits to the default file (or the
  // user extension at ~/.config/omarchy/extensions/omarchy-menu.jsonc) take
  // effect without restarting the shell.
  FileView {
    id: defaultMenuFile
    path: root.defaultMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.defaultMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  FileView {
    id: userMenuFile
    path: root.userMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.userMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onLoadFailed: { root.userMenuItems = []; root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  // ---------------------------------------------------------------- guards
  //
  // `when:` (visibility) and `checked:` (✓ marker) are bash expressions the
  // shell wasn't allowed to evaluate before the perf rewrite. Now the shell
  // batches them into one bash subprocess per (re)load so the open path
  // never has to wait on them.

  property var whenResults: ({})       // id → true|false (allow visibility)
  property var checkedResults: ({})    // id → true|false (show ✓)

  function evaluateGuards() {
    var script = ""
    var ids = Object.keys(root.items)
    for (var i = 0; i < ids.length; i++) {
      var entry = root.items[ids[i]]
      if (!entry) continue
      if (entry.when) script += "if " + entry.when + " >/dev/null 2>&1; then echo " + ids[i] + ":w:1; else echo " + ids[i] + ":w:0; fi\n"
      if (entry.checked) script += "if " + entry.checked + " >/dev/null 2>&1; then echo " + ids[i] + ":c:1; else echo " + ids[i] + ":c:0; fi\n"
    }
    if (!script) {
      root.whenResults = ({})
      root.checkedResults = ({})
      return
    }
    guardProc.collected = ""
    guardProc.command = ["bash", "-lc", script]
    guardProc.running = true
  }

  Process {
    id: guardProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { guardProc.collected += data + "\n" }
    }
    onExited: {
      var nextWhen = ({})
      var nextChecked = ({})
      var lines = guardProc.collected.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line) continue
        var colon = line.lastIndexOf(":")
        if (colon < 0) continue
        var value = line.substring(colon + 1) === "1"
        var rest = line.substring(0, colon)
        var tagAt = rest.lastIndexOf(":")
        if (tagAt < 0) continue
        var id = rest.substring(0, tagAt)
        var tag = rest.substring(tagAt + 1)
        if (tag === "w") nextWhen[id] = value
        else if (tag === "c") nextChecked[id] = value
      }
      root.whenResults = nextWhen
      root.checkedResults = nextChecked
      if (root.opened) root.rebuildDisplay()
    }
  }
  PanelWindow {
    id: panel
    visible: root.opened && root.rowsLoaded
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }

    Rectangle {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      border.color: root.border
      border.width: Math.max(1, Style.space(2))

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.cancel()
            event.accepted = true
          } else if (event.key === Qt.Key_Backspace) {
            if (root.filterText.length > 0) root.setFilter(root.filterText.slice(0, -1))
            else root.goBack()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            if (!root.filterText) root.goBack()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
            if (root.dmenuActive) {
              if (root.mode === "input") root.applyDmenuSelection(root.filterText)
              else if (displayModel.count > 0) root.activateIndex(root.cursorActive ? root.selectedIndex : 0)
            } else if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.margins: root.contentMargin
        spacing: root.contentSpacing

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"
          border.width: 0

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || (root.dmenuActive ? (root.dmenuPrompt + "…") : ((root.item(root.activeMenu) ? root.item(root.activeMenu).label : "Go") + "…"))
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

        }

        Item {
          width: parent.width
          height: root.visibleRowsHeight

          ListView {
            id: resultList
            anchors.fill: parent
            model: displayModel
            clip: true
            spacing: root.rowSpacing
            boundsBehavior: Flickable.StopAtBounds

            section.property: "section"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
              required property string section

              width: ListView.view.width
              height: section === "drilldown" ? root.dividerHeight : 0
              visible: section === "drilldown"

              Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(4)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.spacing.hairline
                color: root.withAlpha(root.foreground, 0.2)
              }
            }

            delegate: Rectangle {
              id: row
              required property int index
              required property string itemId
              required property string kind
              required property string icon
              required property string label
              required property string target
              required property string detail
              required property string path
              required property string action
              required property int childCount

              readonly property bool hasCursor: root.cursorActive && row.index === root.selectedIndex

              width: ListView.view.width
              height: root.rowHeightForDetail(row.detail)
              radius: root.cornerRadius
              color: row.hasCursor ? root.selectedBackground : "transparent"
              border.color: row.hasCursor ? root.selectedBorder : "transparent"
              border.width: (row.hasCursor && root.selectedBorder.a > 0) ? Style.hoverBorderWidth : 0

              Rectangle {
                visible: false
                width: Style.space(4)
                height: parent.height - Style.space(18)
                radius: Math.min(root.cornerRadius, Style.space(4))
                color: root.selectedBackground
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: iconText
                text: row.icon
                color: row.hasCursor ? root.selectedText : root.foreground
                opacity: row.kind === "back" ? 0.7 : 1
                font.family: root.fontFamily
                font.pixelSize: Style.font.iconLarge
                width: Style.space(36)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
              }

              Column {
                id: contentColumn
                anchors.left: iconText.right
                anchors.leftMargin: Style.space(6)
                anchors.right: trail.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                Text {
                  id: labelText
                  width: parent.width
                  text: row.label
                  color: row.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.weight: Font.Medium
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: row.detail
                  visible: root.filterText && row.detail.length > 0
                  color: root.foreground
                  opacity: 0.52
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }

              Row {
                id: trail
                width: Style.space(14)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
                spacing: 0

                Text {
                  visible: false
                  text: row.childCount
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: row.kind === "menu" || row.kind === "link" ? "›" : ""
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: row.kind === "menu" || row.kind === "link" ? 0.36 : 0
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.weight: Font.Normal
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) {
                  root.cursorActive = true
                  root.selectedIndex = row.index
                }
                onClicked: root.activateIndex(row.index)
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0 && root.mode !== "input"

            Text {
              text: "󰈉"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(320)
            }

            Text {
              text: root.filterText ? "No matches for “" + root.filterText + "”" : "Nothing here yet"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(320)
            }
          }
        }

        Item {
          width: parent.width
          height: 0
        }
      }
    }
  }
}
