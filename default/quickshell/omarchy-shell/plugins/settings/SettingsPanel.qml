import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons

import "../../ui/settings" as SettingsUi
import "./components" as Cmp

Item {
  id: root

  // ---------------- plugin lifecycle ---------------------------------------
  property bool closingFromHost: false

  function open(payloadJson) {
    closingFromHost = false
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    if (payload && typeof payload.category === "string" && root.categoryIds.indexOf(payload.category) !== -1) {
      root.activeCategory = payload.category
    } else if (payload && (payload.focusWidgetId || payload.section || payload.focusPluginId)) {
      // Noctalia-compat callers ask us to focus a specific widget/plugin —
      // route them to the relevant tab. Widgets live under Bar; otherwise
      // open the Plugins tab.
      root.activeCategory = payload.focusPluginId ? "plugins" : "bar"
    }

    root.syncSidebarIndexFromCategory()
    root.focusZone = "sidebar"
    window.visible = true
    Qt.callLater(parkFocusOnSink)
  }

  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }

  // ---------------- host injections ----------------------------------------
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var shell: null

  // ---------------- paths --------------------------------------------------
  property string omarchyPath: {
    var env = Quickshell.env("OMARCHY_PATH")
    if (env) return env
    var dir = String(Quickshell.shellDir || "")
    if (dir.indexOf("/default/quickshell/omarchy-shell") !== -1)
      return dir.substring(0, dir.indexOf("/default/quickshell/omarchy-shell"))
    return Quickshell.env("HOME") + "/.local/share/omarchy"
  }
  readonly property string home: Quickshell.env("HOME")
  readonly property string userConfigPath: home + "/.config/omarchy/shell.json"
  readonly property string defaultsPath: omarchyPath + "/default/quickshell/omarchy-shell/shell-defaults.json"
  readonly property string styleStatePath: home + "/.local/state/omarchy/toggles/quickshell-menu.json"

  // ---------------- theme --------------------------------------------------
  // Settings panel deliberately isn't a themable surface in shell.toml —
  // it tracks the foundational palette so every theme renders consistently.
  property color foreground: Color.foreground
  property color background: Color.background
  property color accent: Color.accent
  property color urgent: Color.urgent
  property string fontFamily: "monospace"

  // Source-of-truth for the shell-wide corner radius. Mirrors what the menu
  // reads from quickshell-menu.json so `omarchy style corners <sharp|round>`
  // flips both surfaces together.
  property int cornerRadius: 0

  // Active Omarchy theme name (read from current/theme.name) so the sidebar
  // footer + modeline can surface it without re-parsing colors.toml.
  property string themeName: ""

  // Version label shown in the title bar.
  property string omarchyVersion: ""

  // ---------------- bar-section selection ----------------------------------
  // Which widget row is "selected" in the Bar tab. Drives the modeline
  // readout, the ▶ indicator, and the action keys (J/K reorder, 1-3 zone
  // jump, dd remove). Updated whenever a WidgetRow takes activeFocus.
  property string selectedSection: ""   // "left" | "center" | "right" | ""
  property int selectedIndex: -1

  // Vim-style editor mode. We only ship NORMAL — the property is here so
  // the modeline label stays a single source of truth for future modes.
  property string editorMode: "NORMAL"

  // `dd` two-keystroke remove state. Pressing `d` once arms removal for a
  // brief window; pressing `d` again within that window fires it. Any other
  // key resets the timer. Modeled on vim's dd.
  property bool dPending: false

  // Help overlay toggle (`?` opens it).
  property bool helpOpen: false

  // ---------------- navigation ---------------------------------------------
  readonly property var categoryIds: ["defaults", "style", "bar", "system", "plugins"]
  property string activeCategory: "defaults"

  // Keyboard nav state. Two zones: "sidebar" (j/k cycles category) and
  // "body" (j/k walks through visible focusable controls). Tab/Enter/l/Right
  // dive from sidebar into body; h/Left/Esc backs out.
  property string focusZone: "sidebar"
  property int sidebarIndex: 0

  // Focus visuals — deliberately *different* from selected styling so the
  // keyboard cursor never gets confused with the current value/choice. A
  // selected control gets a 2px accent border; a focused control gets a 3px
  // accent border plus a noticeably tinted accent background.
  readonly property color focusBorderColor: accent
  readonly property color focusFillColor: Qt.rgba(accent.r, accent.g, accent.b, 0.22)
  readonly property int focusBorderWidth: 3

  function syncSidebarIndexFromCategory() {
    var idx = categoryIds.indexOf(activeCategory)
    if (idx >= 0) sidebarIndex = idx
  }

  function setSidebarIndex(i) {
    if (categoryIds.length === 0) return
    if (i < 0) i = categoryIds.length - 1
    if (i >= categoryIds.length) i = 0
    sidebarIndex = i
    activeCategory = categoryIds[i]
  }

  function enterBodyZone() {
    focusZone = "body"
    Qt.callLater(focusFirstBodyItem)
  }

  function exitBodyZone() {
    focusZone = "sidebar"
    parkFocusOnSink()
  }

  // Move activeFocus to a dedicated sink Item that lives outside the body
  // tree. Just clearing focus on the previously focused descendant isn't
  // enough — controls like ComboBox keep an internal focused child that
  // FocusScope happily restores. Forcing focus onto a known sink reliably
  // clears every body focus ring.
  function parkFocusOnSink() {
    if (typeof navFocusSink !== "undefined" && navFocusSink) navFocusSink.forceActiveFocus()
    else if (navRoot) navRoot.forceActiveFocus()
  }

  // Walk the visible body subtree and collect any item with
  // `activeFocusOnTab: true`. Filters out invisible categories so j/k stays
  // within the active tab.
  function gatherBodyFocusables() {
    var arr = []
    function walk(item) {
      if (!item || !item.visible || item.enabled === false) return
      if (item.activeFocusOnTab === true) arr.push(item)
      var children = item.children
      if (!children) return
      for (var i = 0; i < children.length; i++) walk(children[i])
    }
    if (typeof bodyScroll !== "undefined" && bodyScroll && bodyScroll.contentItem)
      walk(bodyScroll.contentItem)
    return arr
  }

  function focusFirstBodyItem() {
    var items = gatherBodyFocusables()
    if (items.length > 0) {
      items[0].forceActiveFocus()
      ensureBodyItemVisible(items[0])
    } else if (navRoot) {
      navRoot.forceActiveFocus()
    }
  }

  function focusBodyDelta(delta) {
    var items = gatherBodyFocusables()
    if (items.length === 0) { exitBodyZone(); return }
    var current = -1
    for (var i = 0; i < items.length; i++) {
      if (items[i].activeFocus) { current = i; break }
    }
    var next = current < 0 ? 0 : current + delta
    if (next < 0) next = items.length - 1
    if (next >= items.length) next = 0
    items[next].forceActiveFocus()
    ensureBodyItemVisible(items[next])
  }

  // Jump to the section whose header reads `[idx] ...` (BracketedFrame,
  // SectionEditor, and RadioSelector all expose `sectionIndex`). Focuses
  // the first focusable descendant if any; otherwise just scrolls the
  // section into view. Returns true if a matching section was found.
  function focusSectionByIndex(idx) {
    if (idx <= 0) return false
    var match = null
    function findSection(item) {
      if (match) return
      if (!item || !item.visible || item.enabled === false) return
      if (item.sectionIndex === idx) { match = item; return }
      var ch = item.children
      if (!ch) return
      for (var i = 0; i < ch.length; i++) findSection(ch[i])
    }
    if (typeof bodyScroll !== "undefined" && bodyScroll && bodyScroll.contentItem) {
      findSection(bodyScroll.contentItem)
    }
    if (!match) return false

    var focusable = null
    function findFocusable(item) {
      if (focusable) return
      if (!item || !item.visible || item.enabled === false) return
      if (item.activeFocusOnTab === true) { focusable = item; return }
      var ch = item.children
      if (!ch) return
      for (var i = 0; i < ch.length; i++) findFocusable(ch[i])
    }
    findFocusable(match)
    if (focusable) {
      focusable.forceActiveFocus()
      ensureBodyItemVisible(focusable)
    } else {
      ensureBodyItemVisible(match)
    }
    return true
  }

  // Scroll the bodyScroll Flickable so `item` is fully on-screen, with a
  // little padding above/below.
  function ensureBodyItemVisible(item) {
    if (!item || typeof bodyScroll === "undefined" || !bodyScroll || !bodyScroll.contentItem) return
    var pos = item.mapToItem(bodyScroll.contentItem, 0, 0)
    var pad = 24
    var top = pos.y - pad
    var bottom = pos.y + item.height + pad
    if (top < bodyScroll.contentY) {
      bodyScroll.contentY = Math.max(0, top)
    } else if (bottom > bodyScroll.contentY + bodyScroll.height) {
      var maxY = Math.max(0, bodyScroll.contentHeight - bodyScroll.height)
      bodyScroll.contentY = Math.min(maxY, bottom - bodyScroll.height)
    }
  }

  onActiveCategoryChanged: {
    syncSidebarIndexFromCategory()
    if (focusZone === "body") Qt.callLater(focusFirstBodyItem)
    else parkFocusOnSink()
  }

  // ---------------- bundled defaults ---------------------------------------
  readonly property var builtinShellConfig: ({
    version: 1,
    bar: {
      position: "top",
      fontFamily: "monospace",
      centerAnchor: "calendar",
      layout: {
        left: [{ id: "omarchy" }, { id: "workspaces" }, { id: "activeWindow" }],
        center: [
          { id: "media" },
          { id: "calendar", format: "dddd HH:mm", formatAlt: "dd MMMM 'W'ww yyyy", verticalFormat: "HH\n—\nmm" },
          { id: "weatherFlyout" }, { id: "update" }, { id: "voxtype" },
          { id: "screenRecording" }, { id: "idle" }, { id: "notifications" }
        ],
        right: [
          { id: "tray" }, { id: "systemStats" }, { id: "microphone" },
          { id: "bluetoothPanel" }, { id: "networkPanel" }, { id: "audioPanel" },
          { id: "battery" }, { id: "controlCenter" }
        ]
      }
    },
    plugins: []
  })

  property var defaultConfig: builtinShellConfig
  property var draft: ({ version: 1, bar: { position: "top", centerAnchor: "calendar", layout: { left: [], center: [], right: [] } }, plugins: [] })
  property int draftRevision: 0
  property bool suppressReload: false

  // ---------------- draft helpers ------------------------------------------
  function cloneJson(value) { return JSON.parse(JSON.stringify(value || null)) }
  function isPlainObject(value) { return value !== null && typeof value === "object" && !Array.isArray(value) }

  function normalizeLayoutEntry(entry) {
    if (typeof entry === "string") return { id: entry }
    if (isPlainObject(entry) && entry.id) return cloneJson(entry)
    return null
  }

  function normalizeLayout(layout) {
    var sections = ["left", "center", "right"]
    var result = {}
    for (var i = 0; i < sections.length; i++) {
      var s = sections[i]
      var arr = []
      var src = (layout && layout[s]) || []
      for (var j = 0; j < src.length; j++) {
        var entry = normalizeLayoutEntry(src[j])
        if (entry) arr.push(entry)
      }
      result[s] = arr
    }
    return result
  }

  function normalizeDraft(source) {
    var bar = isPlainObject(source.bar) ? source.bar : {}
    var plugins = Array.isArray(source.plugins) ? source.plugins.slice() : []
    return {
      version: 1,
      bar: {
        position: String(bar.position || "top"),
        centerAnchor: String(bar.centerAnchor || ""),
        fontFamily: "monospace",
        layout: normalizeLayout(bar.layout || {})
      },
      plugins: plugins
        .map(normalizeLayoutEntry)
        .filter(function(e) {
          if (!e) return false
          var manifest = root.pluginRegistry ? root.pluginRegistry.installedPlugins[e.id] : null
          if (manifest && manifest.__isFirstParty) return false
          return true
        })
    }
  }

  function loadConfig() {
    var defaults = builtinShellConfig
    var diskText = defaultsFile.text()
    if (diskText) {
      try {
        var parsed = JSON.parse(diskText)
        if (isPlainObject(parsed) && parsed.version === 1) defaults = parsed
      } catch (e) {
        console.warn("Bad shell-defaults JSON, falling back to builtin:", e)
        defaults = builtinShellConfig
      }
    }
    defaultConfig = defaults

    var userText = userFile.text() || ""
    var source = defaults
    if (userText.trim()) {
      try {
        var u = JSON.parse(userText)
        if (isPlainObject(u) && u.version === 1) source = u
      } catch (e) {
        console.warn("shell.json parse failed in panel:", e)
      }
    }
    draft = normalizeDraft(source)
    draftRevision++
  }

  function persistDraft() {
    suppressReload = true
    userFile.setText(JSON.stringify(draft, null, 2) + "\n")
  }

  function resetToDefaults() {
    var source = defaultConfig
    if (!isPlainObject(source) || !isPlainObject(source.bar) || !isPlainObject(source.bar.layout)) {
      source = builtinShellConfig
    } else {
      var l = source.bar.layout
      var anyEntries = (l.left && l.left.length) || (l.center && l.center.length) || (l.right && l.right.length)
      if (!anyEntries) source = builtinShellConfig
    }
    var payload = normalizeDraft(source)
    draft = payload
    draftRevision++
    suppressReload = true
    userFile.setText(JSON.stringify(payload, null, 2) + "\n")
  }

  function markDirty() {
    draftRevision++
    persistDraft()
  }

  function sectionArray(section) {
    if (section === "plugins") return draft.plugins || []
    return (draft.bar && draft.bar.layout && draft.bar.layout[section]) || []
  }

  function mutateSection(section, mutator) {
    var arr = sectionArray(section).slice()
    mutator(arr)
    var nextDraft = cloneJson(draft)
    if (section === "plugins") nextDraft.plugins = arr
    else nextDraft.bar.layout[section] = arr
    draft = nextDraft
    markDirty()
  }

  function moveEntry(section, fromIndex, toIndex) {
    var arr = sectionArray(section)
    if (toIndex < 0 || toIndex >= arr.length) return
    mutateSection(section, function(a) {
      var item = a[fromIndex]
      a.splice(fromIndex, 1)
      a.splice(toIndex, 0, item)
    })
  }

  function removeEntry(section, index) {
    mutateSection(section, function(a) { a.splice(index, 1) })
  }

  function addEntry(section, id) {
    mutateSection(section, function(a) { a.push({ id: id }) })
  }

  function updateEntry(section, index, newEntry) {
    mutateSection(section, function(a) { a[index] = cloneJson(newEntry) })
  }

  function loadStyleState(raw) {
    try {
      var s = JSON.parse(raw || "{}")
      var n = Number(s.radius)
      cornerRadius = isFinite(n) ? n : 0
    } catch (e) {
      cornerRadius = 0
    }
  }

  // ---------------- bar-section keyboard ops -------------------------------
  // J/K reorder within the selected widget's section.
  function moveSelectedWithin(delta) {
    if (root.activeCategory !== "bar") return
    if (!root.selectedSection || root.selectedIndex < 0) return
    var arr = root.sectionArray(root.selectedSection)
    var next = root.selectedIndex + delta
    if (next < 0 || next >= arr.length) return
    root.moveEntry(root.selectedSection, root.selectedIndex, next)
    root.selectedIndex = next
    Qt.callLater(refocusSelected)
  }

  // 1/2/3 zone-jump: move the selected widget to left/center/right.
  // Silently refuses duplicates that can't go in two sections at once.
  function moveSelectedToSection(targetSection) {
    if (root.activeCategory !== "bar") return
    if (!root.selectedSection || root.selectedIndex < 0) return
    if (root.selectedSection === targetSection) return
    var arr = root.sectionArray(root.selectedSection)
    if (root.selectedIndex >= arr.length) return
    var entry = arr[root.selectedIndex]
    if (!entry || !entry.id) return

    var allowsMultiple = root.widgetAllowsMultiple(entry.id)
    if (!allowsMultiple) {
      var target = root.sectionArray(targetSection)
      for (var i = 0; i < target.length; i++) {
        if (target[i].id === entry.id) return
      }
    }

    var newDraft = root.cloneJson(root.draft)
    newDraft.bar.layout[root.selectedSection].splice(root.selectedIndex, 1)
    newDraft.bar.layout[targetSection].push(root.cloneJson(entry))
    root.draft = newDraft
    root.markDirty()

    root.selectedSection = targetSection
    root.selectedIndex = newDraft.bar.layout[targetSection].length - 1
    Qt.callLater(refocusSelected)
  }

  // dd: remove the selected widget, then clear the pending flag.
  function fireSelectedDelete() {
    if (root.activeCategory !== "bar") return
    if (!root.selectedSection || root.selectedIndex < 0) return
    var arr = root.sectionArray(root.selectedSection)
    if (root.selectedIndex >= arr.length) return
    var wasAt = root.selectedIndex
    root.removeEntry(root.selectedSection, root.selectedIndex)
    var nextLen = root.sectionArray(root.selectedSection).length
    root.selectedIndex = Math.min(wasAt, nextLen - 1)
    Qt.callLater(refocusSelected)
  }

  // Mouse drag-and-drop: place the widget at `sourceSection[sourceIndex]` into
  // `targetSection` at `targetIndex` (insertion index — 0 means "before first",
  // length means "append"). Mirrors the within/cross-section rules used by
  // J/K and 1-3 so the two input modes stay consistent.
  function dropWidget(sourceSection, sourceIndex, targetSection, targetIndex) {
    if (root.activeCategory !== "bar") return
    if (!sourceSection || sourceIndex < 0 || !targetSection) return
    var srcArr = root.sectionArray(sourceSection)
    if (sourceIndex >= srcArr.length) return
    var entry = srcArr[sourceIndex]
    if (!entry || !entry.id) return

    if (sourceSection === targetSection) {
      // Within-section: removing the source first shifts later indices, so a
      // drop targeted after the source needs to be decremented.
      var adjusted = targetIndex > sourceIndex ? targetIndex - 1 : targetIndex
      if (adjusted < 0) adjusted = 0
      if (adjusted > srcArr.length - 1) adjusted = srcArr.length - 1
      if (adjusted === sourceIndex) return
      root.moveEntry(sourceSection, sourceIndex, adjusted)
      root.selectedSection = sourceSection
      root.selectedIndex = adjusted
    } else {
      // Cross-section: refuse duplicates the widget can't tolerate.
      if (!root.widgetAllowsMultiple(entry.id)) {
        var tgtArr = root.sectionArray(targetSection)
        for (var i = 0; i < tgtArr.length; i++) {
          if (tgtArr[i].id === entry.id) return
        }
      }
      var newDraft = root.cloneJson(root.draft)
      newDraft.bar.layout[sourceSection].splice(sourceIndex, 1)
      var insertAt = Math.max(0, Math.min(targetIndex, newDraft.bar.layout[targetSection].length))
      newDraft.bar.layout[targetSection].splice(insertAt, 0, root.cloneJson(entry))
      root.draft = newDraft
      root.markDirty()
      root.selectedSection = targetSection
      root.selectedIndex = insertAt
    }
    Qt.callLater(refocusSelected)
  }

  // Re-focus the WidgetRow that matches selectedSection/Index after a draft
  // mutation rebuilds the delegates.
  function refocusSelected() {
    if (root.activeCategory !== "bar") return
    var items = gatherBodyFocusables()
    for (var i = 0; i < items.length; i++) {
      var it = items[i]
      if (it && it.barRowMarker === true
          && it.sectionKey === root.selectedSection
          && it.entryIndex === root.selectedIndex) {
        it.forceActiveFocus()
        ensureBodyItemVisible(it)
        return
      }
    }
  }

  // "01", "02", ... — JS String.padStart isn't available on every Qt JS
  // engine version, so do it by hand.
  function padTwo(n) {
    var s = String(n)
    return s.length >= 2 ? s : ("0" + s)
  }

  // Modeline left-side readout. Mirrors :command NORMAL · context · selection
  // so the bar reads like a vim status line.
  function modelineLeft() {
    var prefix = ":" + (root.activeCategory || "settings") + " " + root.editorMode
    if (root.dPending) prefix += "  d_"
    var pieces = [prefix]
    switch (root.activeCategory) {
    case "bar":
      if (root.selectedSection) {
        var arr = root.sectionArray(root.selectedSection)
        pieces.push(arr.length + " " + root.selectedSection + (arr.length === 1 ? " widget" : " widgets"))
        if (root.selectedIndex >= 0 && root.selectedIndex < arr.length) {
          pieces.push(root.widgetName(arr[root.selectedIndex].id) + " selected")
        }
      }
      break
    case "defaults":
      pieces.push("3 groups")
      break
    case "style":
      pieces.push("4 sections")
      pieces.push("auto-saves on")
      break
    case "system":
      pieces.push("2 sections")
      break
    case "plugins":
      pieces.push((root.pluginRegistry ? Object.keys(root.pluginRegistry.installedPlugins).length : 0) + " plugins")
      break
    }
    return pieces.join("  ·  ")
  }

  function modelineRight() {
    switch (root.activeCategory) {
    case "bar":
      return "j/k move    J/K reorder    N jump    ⇧1-3 zone    dd remove    ? help"
    case "defaults":
      return "j/k move    N jump    space select    h back    ? help"
    case "style":
      return "j/k move    N jump    space toggle    h back    ? help"
    case "system":
      return "j/k move    N jump    space toggle    h back    ? help"
    case "plugins":
      return "j/k move    space toggle    h back    ? help"
    }
    return "j/k move    h back    ? help"
  }

  // FileView for theme name. Watches current/theme.name (overwritten in place
  // on theme swap) so the sidebar footer + modeline track live.
  FileView {
    path: root.home + "/.config/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onLoaded: root.themeName = String(text() || "").replace(/\s+$/g, "")
    onFileChanged: reload()
  }

  // Version string for the title-bar suffix.
  FileView {
    path: root.omarchyPath + "/version"
    watchChanges: true
    printErrors: false
    onLoaded: root.omarchyVersion = String(text() || "").replace(/\s+$/g, "")
    onFileChanged: reload()
  }

  // Cancels a pending `dd` if the second `d` doesn't arrive quickly.
  Timer {
    id: deleteTimer
    interval: 700
    onTriggered: root.dPending = false
  }

  // ---------------- widget catalog -----------------------------------------
  readonly property var legacyWidgetMeta: ({
    "omarchy":          { name: "Omarchy menu",       description: "Launches the Omarchy menu",                category: "Compositor" },
    "workspaces":       { name: "Workspaces",         description: "Workspace number indicators",              category: "Compositor" },
    "clock":            { name: "Clock",              description: "Date / time text",                          category: "Time" },
    "weather":          { name: "Weather (legacy)",   description: "Tiny weather pill",                          category: "Info" },
    "update":           { name: "Updates",            description: "Indicates available system updates",        category: "System" },
    "voxtype":          { name: "Voxtype",            description: "Voxtype dictation state",                   category: "Status" },
    "screenRecording":  { name: "Screen recording",   description: "Active recording indicator",                category: "Status" },
    "idle":             { name: "Idle (legacy)",      description: "Inhibitor indicator",                        category: "Status" },
    "notifications":    { name: "DND",                 description: "Do-not-disturb indicator",                 category: "Status" },
    "tray":             { name: "System tray",        description: "Status notifier items",                     category: "Status" },
    "bluetooth":        { name: "Bluetooth (legacy)", description: "Bluetooth status icon",                    category: "Network" },
    "network":          { name: "Network (legacy)",   description: "Wi-Fi / ethernet status",                    category: "Network" },
    "audio":            { name: "Volume (legacy)",    description: "Speaker icon, scroll for volume",            category: "Audio" },
    "cpu":              { name: "CPU (legacy)",       description: "btop launcher",                              category: "System" },
    "battery":          { name: "Battery",            description: "Battery percent and ETA",                   category: "System" }
  })

  property int catalogRevision: 0
  onBarWidgetRegistryChanged: {
    catalogRevision++
    if (!root.barWidgetRegistry) return
    console.log("settings panel open. omarchyPath=" + root.omarchyPath,
      "defaultsPath=" + root.defaultsPath,
      "userConfigPath=" + root.userConfigPath,
      "registry has",
      root.barWidgetRegistry.availableIds().length,
      "widgets")
  }
  Connections {
    target: root.barWidgetRegistry
    function onChanged() { root.catalogRevision++ }
  }

  function widgetMetadata(id) {
    var key = String(id || "")
    if (root.barWidgetRegistry && root.barWidgetRegistry.has(key))
      return root.barWidgetRegistry.metadataFor(key) || {}
    if (legacyWidgetMeta[key]) return legacyWidgetMeta[key]

    var manifest = root.pluginRegistry ? root.pluginRegistry.installedPlugins[key] : null
    if (manifest) {
      var meta = manifest.barWidget || {}
      return {
        displayName: meta.displayName || manifest.name || key,
        name: meta.displayName || manifest.name || key,
        description: meta.description || manifest.description || "",
        category: meta.category || (manifest.__noctaliaCompat ? "Noctalia" : "Plugin"),
        allowMultiple: meta.allowMultiple === true,
        settingsForm: meta.settingsForm || "",
        schema: Array.isArray(meta.schema) ? meta.schema : [],
        source: "plugin"
      }
    }
    return {}
  }

  function widgetName(id) {
    var rev = catalogRevision
    var meta = widgetMetadata(id)
    return meta.displayName || meta.name || id
  }

  function widgetDescription(id) {
    var rev = catalogRevision
    var meta = widgetMetadata(id)
    return meta.description || ""
  }

  function widgetSchema(id) {
    var meta = widgetMetadata(id)
    return Array.isArray(meta.schema) ? meta.schema : []
  }

  function widgetHasSettings(id) {
    var rev = catalogRevision
    var meta = widgetMetadata(id)
    if (meta.settingsForm) return true
    if (widgetSchema(id).length > 0) return true
    var manifest = root.pluginRegistry ? root.pluginRegistry.installedPlugins[id] : null
    if (manifest && manifest.__noctaliaCompat && manifest.entryPoints && manifest.entryPoints.settings)
      return true
    return false
  }

  function widgetIsNoctaliaPlugin(id) {
    var manifest = root.pluginRegistry ? root.pluginRegistry.installedPlugins[id] : null
    return !!(manifest && manifest.__noctaliaCompat)
  }

  function widgetAllowsMultiple(id) {
    var meta = widgetMetadata(id)
    if (meta.allowMultiple === true) return true
    return String(id) === "spacer"
  }

  function catalogIds() {
    var rev = catalogRevision
    var ids = {}
    if (root.barWidgetRegistry) {
      var registered = root.barWidgetRegistry.availableIds()
      for (var i = 0; i < registered.length; i++) ids[registered[i]] = true
    }
    if (root.pluginRegistry && root.pluginRegistry.installedPlugins) {
      var plugins = root.pluginRegistry.installedPlugins
      for (var pid in plugins) {
        var manifest = plugins[pid]
        if (manifest && Array.isArray(manifest.kinds) && manifest.kinds.indexOf("bar-widget") !== -1)
          ids[pid] = true
      }
    }
    for (var key in legacyWidgetMeta) ids[key] = true
    return Object.keys(ids)
  }

  function availableToAdd(section) {
    var rev = catalogRevision
    var isBarSection = section === "left" || section === "center" || section === "right"
    var barSections = ["left", "center", "right"]

    var existingInBar = {}
    for (var s = 0; s < barSections.length; s++) {
      var list = sectionArray(barSections[s])
      for (var i = 0; i < list.length; i++) existingInBar[list[i].id] = true
    }
    var existingInPlugins = {}
    var pluginList = sectionArray("plugins")
    for (var p = 0; p < pluginList.length; p++) existingInPlugins[pluginList[p].id] = true

    var ids = catalogIds().sort(function(a, b) { return widgetName(a).localeCompare(widgetName(b)) })

    var result = []
    for (var k = 0; k < ids.length; k++) {
      var id = ids[k]
      var meta = widgetMetadata(id)
      var manifest = root.pluginRegistry ? root.pluginRegistry.installedPlugins[id] : null
      var manifestIsBarWidget = manifest && Array.isArray(manifest.kinds) && manifest.kinds.indexOf("bar-widget") !== -1
      var isBarWidget = !!(meta && meta.source !== "plugin") || manifestIsBarWidget
      if (isBarSection) {
        if (!isBarWidget && !legacyWidgetMeta[id]) continue
        var inSection = sectionArray(section)
        var existsHere = false
        for (var x = 0; x < inSection.length; x++) if (inSection[x].id === id) { existsHere = true; break }
        var allowsMultiple = widgetAllowsMultiple(id)
        if (!allowsMultiple && existingInBar[id]) continue
        result.push({ id: id, name: widgetName(id), description: widgetDescription(id),
          elsewhere: allowsMultiple && !!existingInBar[id] && !existsHere,
          isNoctalia: widgetIsNoctaliaPlugin(id) })
      } else {
        if (!manifest) continue
        if (manifest.__isFirstParty) continue
        if (existingInPlugins[id]) continue
        result.push({ id: id, name: widgetName(id), description: widgetDescription(id), elsewhere: false,
          isNoctalia: widgetIsNoctaliaPlugin(id) })
      }
    }
    return result
  }

  // ---------------- file watchers ------------------------------------------
  FileView {
    id: defaultsFile
    path: root.defaultsPath
    watchChanges: true
    printErrors: true
    onLoaded: root.loadConfig()
    onLoadFailed: function(error) { console.warn("defaults load failed:", error, "path=" + root.defaultsPath) }
    onFileChanged: reload()
  }

  FileView {
    id: userFile
    path: root.userConfigPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      if (root.suppressReload) { root.suppressReload = false; return }
      root.loadConfig()
    }
    onFileChanged: reload()
  }

  FileView {
    path: root.styleStatePath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadStyleState(text())
    onFileChanged: reload()
  }

  // ---------------- window -------------------------------------------------
  FloatingWindow {
    id: window
    title: "Omarchy Settings"
    color: root.background
    implicitWidth: 880
    implicitHeight: 620
    minimumSize: Qt.size(700, 480)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide("omarchy.settings")
      if (visible) Qt.callLater(root.parkFocusOnSink)
    }

    FocusScope {
      id: navRoot
      anchors.fill: parent
      focus: true

      Component.onCompleted: navFocusSink.forceActiveFocus()

      // Invisible focus sink. When focus belongs to the sidebar (no
      // specific body item focused), activeFocus lives on this 1px Item so
      // body controls render their unfocused state cleanly.
      Item {
        id: navFocusSink
        width: 1
        height: 1
        objectName: "navFocusSink"
      }

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        var ctrl = (event.modifiers & Qt.ControlModifier) !== 0

        if (root.focusZone === "sidebar") {
          switch (event.key) {
          case Qt.Key_J:
          case Qt.Key_Down:
            root.setSidebarIndex(root.sidebarIndex + 1); event.accepted = true; return
          case Qt.Key_K:
          case Qt.Key_Up:
            root.setSidebarIndex(root.sidebarIndex - 1); event.accepted = true; return
          case Qt.Key_L:
          case Qt.Key_Right:
          case Qt.Key_Tab:
          case Qt.Key_Return:
          case Qt.Key_Enter:
            root.enterBodyZone(); event.accepted = true; return
          case Qt.Key_Escape:
            root.close(); event.accepted = true; return
          }
          if (ctrl && event.key === Qt.Key_L) { root.enterBodyZone(); event.accepted = true; return }
        } else {
          // body
          var shift = (event.modifiers & Qt.ShiftModifier) !== 0
          var inBarRow = root.activeCategory === "bar"
            && root.selectedSection !== ""
            && root.selectedIndex >= 0

          // Any non-d key cancels a pending `dd`.
          if (root.dPending && event.key !== Qt.Key_D) {
            root.dPending = false
            deleteTimer.stop()
          }

          // Help overlay swallows everything except `?` and Esc.
          if (root.helpOpen) {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Question) {
              root.helpOpen = false; event.accepted = true; return
            }
            event.accepted = true; return
          }

          switch (event.key) {
          case Qt.Key_Escape:
          case Qt.Key_H:
          case Qt.Key_Left:
          case Qt.Key_Backtab:
            root.exitBodyZone(); event.accepted = true; return
          case Qt.Key_J:
            if (shift && inBarRow) { root.moveSelectedWithin(+1); event.accepted = true; return }
            root.focusBodyDelta(+1); event.accepted = true; return
          case Qt.Key_K:
            if (shift && inBarRow) { root.moveSelectedWithin(-1); event.accepted = true; return }
            root.focusBodyDelta(-1); event.accepted = true; return
          case Qt.Key_Down:
          case Qt.Key_Tab:
            root.focusBodyDelta(+1); event.accepted = true; return
          case Qt.Key_Up:
            root.focusBodyDelta(-1); event.accepted = true; return
          case Qt.Key_Exclam:
          case Qt.Key_At:
          case Qt.Key_NumberSign: {
            // Shift+1/2/3 on a US layout arrives as !/@/# — Qt rewrites the
            // keycode rather than just setting ShiftModifier, so we have to
            // match the shifted variants explicitly.
            if (!inBarRow) { break }
            var shiftZones = ["left", "center", "right"]
            var sz = event.key === Qt.Key_Exclam ? 0
                   : event.key === Qt.Key_At     ? 1 : 2
            root.moveSelectedToSection(shiftZones[sz])
            event.accepted = true; return
          }
          case Qt.Key_1:
          case Qt.Key_2:
          case Qt.Key_3:
          case Qt.Key_4:
          case Qt.Key_5:
          case Qt.Key_6:
          case Qt.Key_7:
          case Qt.Key_8:
          case Qt.Key_9: {
            if (shift) { break }
            var n = event.key - Qt.Key_0
            if (root.focusSectionByIndex(n)) { event.accepted = true; return }
            break
          }
          case Qt.Key_D:
            if (inBarRow) {
              if (root.dPending) {
                root.fireSelectedDelete()
                root.dPending = false
                deleteTimer.stop()
              } else {
                root.dPending = true
                deleteTimer.restart()
              }
              event.accepted = true; return
            }
            break
          case Qt.Key_Question:
            root.helpOpen = true; event.accepted = true; return
          }
          if (ctrl && event.key === Qt.Key_H) { root.exitBodyZone(); event.accepted = true; return }
        }
      }

    Rectangle {
      id: panelContent
      anchors.fill: parent
      color: root.background
      // No explicit border — the Hyprland window decoration already draws one.

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header — title text sits above a hairline divider that runs the
        // full width of the window. No notching: the title is a row in its
        // own right, and the line below it cleanly separates the chrome
        // from the body + sidebar.
        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: 46

          Row {
            id: titleRow
            anchors.left: parent.left
            anchors.leftMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Text {
              text: "[ Omarchy Settings ]"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: 16
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              visible: root.omarchyVersion !== ""
              text: "— v" + root.omarchyVersion
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 13
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Text {
            id: pathLabel
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            text: "~/.config/omarchy/shell.json"
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: 13
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)
        }

        // Sidebar + content
        RowLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 0

          // Sidebar
          Item {
            Layout.preferredWidth: 180
            Layout.fillHeight: true

            Rectangle {
              anchors.fill: parent
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
            }

            ColumnLayout {
              anchors.fill: parent
              anchors.margins: 14
              spacing: 2

              SidebarRow { categoryId: "defaults"; label: "Defaults" }
              SidebarRow { categoryId: "style";    label: "Style" }
              SidebarRow { categoryId: "bar";      label: "Bar" }
              SidebarRow { categoryId: "system";   label: "System" }
              SidebarRow { categoryId: "plugins";  label: "Plugins" }

              Item { Layout.fillHeight: true }

              // Footer: current theme + status. Mirrors the modeline style.
              Column {
                Layout.fillWidth: true
                spacing: 2

                Text {
                  text: "THEME"
                  color: Qt.darker(root.foreground, 1.8)
                  font.family: root.fontFamily
                  font.pixelSize: 10
                  font.bold: true
                }
                Text {
                  text: root.themeName || "—"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: 12
                }
              }

              Item { Layout.preferredHeight: 10 }

              Column {
                Layout.fillWidth: true
                spacing: 2

                Text {
                  text: "STATUS"
                  color: Qt.darker(root.foreground, 1.8)
                  font.family: root.fontFamily
                  font.pixelSize: 10
                  font.bold: true
                }
                Row {
                  spacing: 6

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6; height: 6; radius: 3
                    color: root.accent
                  }
                  Text {
                    text: "Quickshell · running"
                    color: Qt.darker(root.foreground, 1.3)
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
              }
            }
          }

          Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
          }

          // Content
          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Flickable {
              id: bodyScroll
              anchors.fill: parent
              anchors.margins: 18
              clip: true
              contentWidth: width
              contentHeight: contentColumn.implicitHeight
              boundsBehavior: Flickable.StopAtBounds
              flickableDirection: Flickable.VerticalFlick

              ColumnLayout {
                id: contentColumn
                width: bodyScroll.width
                spacing: 14

                BarCategory     { visible: root.activeCategory === "bar"      ; Layout.fillWidth: true }
                PluginManager   { visible: root.activeCategory === "plugins"  ; Layout.fillWidth: true }
                DefaultsCategory{ visible: root.activeCategory === "defaults" ; Layout.fillWidth: true }
                StyleCategory   { visible: root.activeCategory === "style"    ; Layout.fillWidth: true }
                SystemCategory  { visible: root.activeCategory === "system"   ; Layout.fillWidth: true }
              }
            }
          }
        }

        // ----- modeline ------------------------------------------------------
        // Vim-style status line. Left side: command + mode + selection context.
        // Right side: keybinding hints for the active tab.
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
        }

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: 24

          Rectangle {
            anchors.fill: parent
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            // Inline reads ensure QML tracks every dependency that the
            // modeline label depends on, so it re-evaluates correctly.
            text: {
              var _ = [root.activeCategory, root.editorMode,
                       root.selectedSection, root.selectedIndex,
                       root.draftRevision, root.dPending,
                       root.pluginRegistry ? root.pluginRegistry.registryRevision : 0]
              return root.modelineLeft()
            }
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 11
          }

          Text {
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            text: {
              var _ = root.activeCategory
              return root.modelineRight()
            }
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: 11
          }
        }
      }

      // ----- drag ghost ------------------------------------------------------
      // Floating preview chip used to drag a widget row between sections.
      // Lives at the panel-content level (rather than inside the row that
      // started the drag) for two reasons: (1) WidgetRows are pinned by a
      // Column layout and can't move themselves, and DropArea only fires
      // when the *dragged item's* scene position changes; (2) a panel-level
      // owner lets us track the cursor freely across all three sections.
      // The chip is moved imperatively by each row's MouseArea when a drag
      // is in flight. `sourceSection`/`sourceIndex` snapshot which row is
      // being dragged so DropAreas can read it off `drag.source`.
      Item {
        id: dragGhost
        width: 240
        height: 26
        // Visibility follows Drag.active so the chip disappears as soon as
        // the drop completes — drop handlers mutate the draft, which
        // destroys the source row's MouseArea before its onReleased can
        // finish cleaning up imperatively.
        visible: Drag.active
        z: 90
        opacity: 0.92

        property string sourceSection: ""
        property int sourceIndex: -1
        property string sourceName: ""

        Drag.source: dragGhost
        Drag.keys: ["omarchy-bar-widget"]
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2

        Rectangle {
          anchors.fill: parent
          color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.20)
          border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.75)
          border.width: 1
          radius: root.cornerRadius
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: 12
          anchors.right: parent.right
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          text: dragGhost.sourceName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: 12
          elide: Text.ElideRight
        }
      }

      // ----- help overlay ----------------------------------------------------
      // Pressed `?` to toggle. Lists the bar-tab keybindings. Dismiss with
      // `?`, Esc, or click outside.
      Rectangle {
        anchors.fill: parent
        visible: root.helpOpen
        color: Qt.rgba(0, 0, 0, 0.55)
        z: 100

        MouseArea {
          anchors.fill: parent
          onClicked: root.helpOpen = false
        }

        Rectangle {
          anchors.centerIn: parent
          width: 540
          height: helpColumn.implicitHeight + 56
          color: root.background
          border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.7)
          border.width: 1
          radius: root.cornerRadius

          // Notched title on the top border.
          Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 22
            anchors.top: parent.top
            anchors.topMargin: -helpTitle.implicitHeight / 2 - 2
            width: helpTitle.implicitWidth + 18
            height: helpTitle.implicitHeight + 6
            color: root.background

            Text {
              id: helpTitle
              anchors.centerIn: parent
              text: "[ Keybindings ]"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
          }

          ColumnLayout {
            id: helpColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 28
            anchors.rightMargin: 28
            anchors.topMargin: 24
            spacing: 8

            Repeater {
              model: [
                { keys: "j   k",        action: "move focus down / up" },
                { keys: "h   l",        action: "exit / enter body" },
                { keys: "J   K",        action: "reorder widget within section" },
                { keys: "1 … 9",        action: "jump to section [N]" },
                { keys: "⇧1   ⇧2   ⇧3", action: "move widget to left / center / right (in bar row)" },
                { keys: "d d",          action: "remove selected widget" },
                { keys: "drag",         action: "drag a widget to reorder or move between sections" },
                { keys: "Tab",          action: "next focusable control" },
                { keys: "Esc",          action: "close panel (sidebar) / back to sidebar (body)" },
                { keys: "?",            action: "toggle this overlay" }
              ]
              delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 18

                Text {
                  text: modelData.keys
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: 13
                  font.bold: true
                  Layout.preferredWidth: 100
                }
                Text {
                  text: modelData.action
                  color: Qt.darker(root.foreground, 1.2)
                  font.family: root.fontFamily
                  font.pixelSize: 12
                  Layout.fillWidth: true
                }
              }
            }

            Item { Layout.preferredHeight: 8 }

            Text {
              text: "press ? or Esc to close"
              color: Qt.darker(root.foreground, 1.7)
              font.family: root.fontFamily
              font.pixelSize: 11
              Layout.alignment: Qt.AlignRight
            }
          }
        }
      }
    }
    }
  }

  // ===================== sidebar row =======================================
  // No icon glyph — categories are labeled by name, with a ▶ marker on the
  // active row. Mirrors the vim/tui aesthetic of the rest of the panel.
  component SidebarRow: Rectangle {
    id: sb
    property string categoryId: ""
    property string label: ""
    readonly property bool active: root.activeCategory === categoryId
    readonly property bool sidebarFocused: root.focusZone === "sidebar"

    Layout.fillWidth: true
    Layout.preferredHeight: 28
    radius: root.cornerRadius
    color: sb.active
      ? (sb.sidebarFocused
          ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10))
      : (sbArea.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06) : "transparent")
    border.color: sb.active && sb.sidebarFocused
      ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55)
      : "transparent"
    border.width: sb.active && sb.sidebarFocused ? 1 : 0

    Behavior on color { ColorAnimation { duration: 100 } }

    // Caret indicator. Always reserves space so labels never shift.
    Text {
      text: sb.active ? "▶" : ""
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: 11
      width: 12
      anchors.left: parent.left
      anchors.leftMargin: 8
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      text: sb.label
      color: sb.active ? root.foreground : Qt.darker(root.foreground, 1.25)
      font.family: root.fontFamily
      font.pixelSize: 13
      font.bold: sb.active
      anchors.left: parent.left
      anchors.leftMargin: 26
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      id: sbArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        root.activeCategory = sb.categoryId
        root.focusZone = "sidebar"
        if (navRoot) navRoot.forceActiveFocus()
      }
    }
  }

  // ===================== bar category ======================================
  component BarCategory: ColumnLayout {
    spacing: 16

    // Widget sections come first so Shift+1/2/3 lines up with [1]/[2]/[3]
    // when moving widgets between zones. Position/anchor follow as [4]/[5].
    SectionEditor { sectionKey: "left";    sectionLabel: "Bar · Left";   sectionIndex: 1 }
    SectionEditor { sectionKey: "center";  sectionLabel: "Bar · Center"; sectionIndex: 2 }
    SectionEditor { sectionKey: "right";   sectionLabel: "Bar · Right";  sectionIndex: 3 }

    RadioSelector {
      sectionLabel: "Bar · Position"
      sectionMeta: "where the bar lives on screen"
      sectionIndex: 4
      value: root.draft.bar.position
      options: [
        { value: "top",    label: "top",    description: "above the workspace" },
        { value: "right",  label: "right",  description: "right edge, vertical" },
        { value: "bottom", label: "bottom", description: "below the workspace" },
        { value: "left",   label: "left",   description: "left edge, vertical" }
      ]
      onChanged: function(v) {
        var next = root.cloneJson(root.draft)
        next.bar.position = v
        root.draft = next
        root.markDirty()
      }
    }

    RadioSelector {
      sectionLabel: "Bar · Center anchor"
      sectionMeta: "widget aligned to the bar's midpoint"
      sectionIndex: 5
      value: root.draft.bar.centerAnchor || "(none)"
      options: {
        var list = [{ value: "(none)", label: "(none)", description: "no center anchor" }]
        var entries = root.draft.bar.layout.center || []
        for (var i = 0; i < entries.length; i++) {
          var id = entries[i].id
          list.push({ value: id, label: root.widgetName(id), description: root.widgetDescription(id) })
        }
        return list
      }
      onChanged: function(v) {
        var next = root.cloneJson(root.draft)
        next.bar.centerAnchor = v === "(none)" ? "" : v
        root.draft = next
        root.markDirty()
      }
    }

    // Trailing reset action — kept subtle, right-aligned.
    Row {
      Layout.alignment: Qt.AlignRight
      Layout.topMargin: 6
      ActionPill {
        text: "Reset to defaults"
        foreground: root.urgent
        onClicked: root.resetToDefaults()
      }
    }
  }

  // ===================== defaults category =================================
  component DefaultsCategory: ColumnLayout {
    id: dc
    spacing: 14

    property string terminalCurrent: ""
    property string browserCurrent: ""
    property string editorCurrent: ""
    property int refreshTick: 0

    function refresh() {
      refreshTick++
      readTerminalProc.running = true
      readBrowserProc.running = true
      readEditorProc.running = true
    }

    Process {
      id: readTerminalProc
      command: ["omarchy-default-terminal"]
      stdout: SplitParser { onRead: function(line) { dc.terminalCurrent = String(line).trim() } }
    }
    Process {
      id: readBrowserProc
      command: ["omarchy-default-browser"]
      stdout: SplitParser { onRead: function(line) { dc.browserCurrent = String(line).trim() } }
    }
    Process {
      id: readEditorProc
      command: ["omarchy-default-editor"]
      stdout: SplitParser { onRead: function(line) { dc.editorCurrent = String(line).trim() } }
    }
    // Refresh after the write has actually finished — kicking off a read
    // synchronously after .running = true races the bash apply and ends up
    // displaying the *previous* default.
    Process {
      id: applyDefaultsProc
      onExited: dc.refresh()
    }

    function applyDefault(group, value) {
      var cmd = ""
      if (group === "terminal") cmd = "omarchy-default-terminal " + value
      else if (group === "browser") cmd = "omarchy-default-browser " + value
      else if (group === "editor") cmd = "omarchy-default-editor " + value
      if (!cmd) return
      applyDefaultsProc.command = ["bash", "-lc", cmd]
      applyDefaultsProc.running = true
    }

    Component.onCompleted: refresh()
    onVisibleChanged: if (visible) refresh()

    BracketedFrame {
      sectionIndex: 1
      sectionLabel: "TERMINAL"
      sectionMeta: "Super+Return · xdg-terminal-exec"

      Repeater {
        model: [
          { id: "alacritty", label: "Alacritty", cmd: "alacritty" },
          { id: "foot",      label: "Foot",      cmd: "foot" },
          { id: "ghostty",   label: "Ghostty",   cmd: "ghostty" },
          { id: "kitty",     label: "Kitty",     cmd: "kitty" }
        ]
        delegate: DefaultsRow {
          required property var modelData
          required property int index
          width: parent.width
          rowIndex: index
          optionLabel: modelData.label
          checkCmd: modelData.cmd
          selected: dc.terminalCurrent === modelData.id
          onChosen: dc.applyDefault("terminal", modelData.id)
        }
      }
    }

    BracketedFrame {
      sectionIndex: 2
      sectionLabel: "BROWSER"
      sectionMeta: "x-scheme-handler/http · HTML files"

      Repeater {
        model: [
          { id: "chromium",     label: "Chromium",     cmd: "chromium" },
          { id: "chrome",       label: "Chrome",       cmd: "google-chrome-stable" },
          { id: "brave",        label: "Brave",        cmd: "brave" },
          { id: "brave-origin", label: "Brave Origin", cmd: "brave-origin-beta" },
          { id: "edge",         label: "Edge",         cmd: "microsoft-edge-stable" },
          { id: "firefox",      label: "Firefox",      cmd: "firefox" },
          { id: "zen",          label: "Zen",          cmd: "zen-browser" }
        ]
        delegate: DefaultsRow {
          required property var modelData
          required property int index
          width: parent.width
          rowIndex: index
          optionLabel: modelData.label
          checkCmd: modelData.cmd
          selected: dc.browserCurrent === modelData.id
          onChosen: dc.applyDefault("browser", modelData.id)
        }
      }
    }

    BracketedFrame {
      sectionIndex: 3
      sectionLabel: "EDITOR"
      sectionMeta: "$EDITOR · effective on next login"

      Repeater {
        model: [
          { id: "nvim",         label: "Neovim",       cmd: "nvim" },
          { id: "code",         label: "VSCode",       cmd: "code" },
          { id: "cursor",       label: "Cursor",       cmd: "cursor" },
          { id: "zeditor",      label: "Zed",          cmd: "zeditor" },
          { id: "sublime_text", label: "Sublime Text", cmd: "sublime_text" },
          { id: "helix",        label: "Helix",        cmd: "helix" },
          { id: "vim",          label: "Vim",          cmd: "vim" },
          { id: "emacs",        label: "Emacs",        cmd: "emacs" }
        ]
        delegate: DefaultsRow {
          required property var modelData
          required property int index
          width: parent.width
          rowIndex: index
          optionLabel: modelData.label
          checkCmd: modelData.cmd
          selected: dc.editorCurrent === modelData.id
          onChosen: dc.applyDefault("editor", modelData.id)
        }
      }
    }
  }

  // One terminal/browser/editor option. Wraps NumberedRadioRow with a
  // PATH probe so unavailable commands are dimmed and labeled.
  component DefaultsRow: Item {
    id: dr
    property int rowIndex: 0
    property string optionLabel: ""
    property string checkCmd: ""
    property bool selected: false
    property bool available: false
    signal chosen()

    implicitHeight: nrr.implicitHeight
    width: parent ? parent.width : implicitWidth

    Process {
      id: probeProc
      command: ["bash", "-lc", "command -v " + dr.checkCmd + " >/dev/null && echo yes || echo no"]
      stdout: SplitParser { onRead: function(line) { dr.available = String(line).trim() === "yes" } }
      Component.onCompleted: running = true
    }

    NumberedRadioRow {
      id: nrr
      anchors.left: parent.left
      anchors.right: parent.right
      rowIndex: dr.rowIndex
      label: dr.optionLabel
      detail: dr.checkCmd
      selected: dr.selected
      available: dr.available
      trailing: dr.selected
        ? "default"
        : (dr.available
            ? (nrr.activeFocus ? "press space to set" : "")
            : "not installed")
      trailingColor: dr.selected
        ? root.accent
        : Qt.darker(root.foreground, 1.6)
      onChosen: dr.chosen()
    }
  }

  // ===================== style category ====================================
  component StyleCategory: ColumnLayout {
    id: sc
    spacing: 14

    property string currentCorners: root.cornerRadius > 0 ? "round" : "sharp"
    property bool barOn: true
    property bool gapsOn: true
    property bool oneWinSquare: false
    property string monitorName: ""
    property string monitorScale: ""
    property string fontName: ""
    property var fontsList: []
    property int refreshTick: 0

    function refresh() {
      refreshTick++
      readBarProc.running = true
      readGapsProc.running = true
      readOneWinSqProc.running = true
      readMonitorProc.running = true
      readFontProc.running = true
      readFontsListProc.running = true
    }

    Process { id: applyStyleProc; onExited: sc.refresh() }

    Process {
      id: readFontProc
      command: ["omarchy-font-current"]
      stdout: SplitParser { onRead: function(line) { sc.fontName = String(line).trim() } }
    }
    Process {
      id: readFontsListProc
      command: ["omarchy-font-list"]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: sc.fontsList = String(text || "").trim().split("\n").filter(function(x) { return x.length > 0 })
      }
    }

    // Pick up theme/background changes that happen via the menu / CLI without
    // going through the Style category's own buttons.
    FileView {
      path: root.home + "/.config/omarchy/current/theme.name"
      watchChanges: true
      printErrors: false
      onFileChanged: sc.refresh()
      onLoaded: sc.refresh()
    }
    FileView {
      path: root.home + "/.config/alacritty/alacritty.toml"
      watchChanges: true
      printErrors: false
      onFileChanged: sc.refresh()
    }

    // Re-read when any toggle flag changes on disk — covers CLI/menu paths
    // that mutate `~/.local/state/omarchy/toggles/*` without going through us.
    FileView {
      path: root.home + "/.local/state/omarchy/toggles"
      watchChanges: true
      printErrors: false
      onFileChanged: sc.refresh()
    }
    FileView {
      path: root.home + "/.local/state/omarchy/toggles/hypr"
      watchChanges: true
      printErrors: false
      onFileChanged: sc.refresh()
    }

    Process {
      id: readBarProc
      command: ["bash", "-lc", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo no || echo yes"]
      stdout: SplitParser { onRead: function(line) { sc.barOn = String(line).trim() === "yes" } }
    }
    Process {
      id: readGapsProc
      command: ["bash", "-lc", "[[ -f $HOME/.local/state/omarchy/toggles/hypr/window-no-gaps.lua ]] && echo no || echo yes"]
      stdout: SplitParser { onRead: function(line) { sc.gapsOn = String(line).trim() === "yes" } }
    }
    Process {
      id: readOneWinSqProc
      command: ["bash", "-lc", "[[ -f $HOME/.local/state/omarchy/toggles/hypr/single-window-aspect-ratio.lua ]] && echo yes || echo no"]
      stdout: SplitParser { onRead: function(line) { sc.oneWinSquare = String(line).trim() === "yes" } }
    }
    // Snaps the scale Hyprland reports (which may be fractional / drifted) to
    // the nearest value in the canonical list. Used by the scale picker to
    // know which chip to highlight.
    function snapScale(raw) {
      var n = parseFloat(raw)
      if (!isFinite(n)) return ""
      var scales = ["1", "1.25", "1.6", "2", "3", "4"]
      var best = scales[0], bestDiff = Infinity
      for (var i = 0; i < scales.length; i++) {
        var d = Math.abs(n - parseFloat(scales[i]))
        if (d < bestDiff) { bestDiff = d; best = scales[i] }
      }
      return best
    }

    Process {
      id: readMonitorProc
      command: ["bash", "-lc", "hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused == true) | \"\\(.name)\\t\\(.scale)\"'"]
      stdout: SplitParser { onRead: function(line) {
        var parts = String(line).trim().split("\t")
        if (parts.length >= 2) {
          sc.monitorName = parts[0]
          sc.monitorScale = sc.snapScale(parts[1])
        }
      } }
    }

    function runStyle(cmd) {
      applyStyleProc.command = ["bash", "-lc", cmd]
      applyStyleProc.running = true
    }

    function shortFontName(name) {
      // Strip a trailing " Nerd Font" so the flag stays one token.
      return String(name || "").replace(/\s+Nerd Font(\s+Mono)?$/i, "$1").replace(/\s+/g, "")
    }

    Component.onCompleted: refresh()
    onVisibleChanged: if (visible) refresh()

    BracketedFrame {
      sectionIndex: 1
      sectionLabel: "WINDOWS"
      sectionMeta: "hyprland behavior toggles"

      NumberedToggleRow {
        width: parent.width
        rowIndex: 0
        label: "Window gaps"
        description: "Tile windows with the default gap between them."
        isOn: sc.gapsOn
        onToggle: sc.runStyle("omarchy-hyprland-window-gaps-toggle")
      }
      NumberedToggleRow {
        width: parent.width
        rowIndex: 1
        label: "1-window square ratio"
        description: "Constrain a solo tiled window to a square aspect."
        isOn: sc.oneWinSquare
        onToggle: sc.runStyle("omarchy-hyprland-window-single-square-aspect-toggle")
      }
      NumberedToggleRow {
        width: parent.width
        rowIndex: 2
        label: "Bar"
        description: "Show the omarchy bar."
        isOn: sc.barOn
        onToggle: sc.runStyle("omarchy-toggle-bar")
      }
    }

    BracketedFrame {
      sectionIndex: 2
      sectionLabel: "CORNERS"
      sectionMeta: "Sharp matches the retro TUI look; round softens windows."

      Row {
        spacing: 14

        BracketChip {
          label: "Sharp"
          selected: sc.currentCorners === "sharp"
          onClicked: sc.runStyle("omarchy-style-corners sharp")
        }
        BracketChip {
          label: "Round"
          selected: sc.currentCorners === "round"
          onClicked: sc.runStyle("omarchy-style-corners round")
        }
      }

      Item { width: 1; height: 4 }

      Row {
        spacing: 8

        Text {
          text: sc.currentCorners === "sharp" ? "0px radius" : "6px radius"
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: 12
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          text: "·  windows, menus, notifications"
          color: Qt.darker(root.foreground, 1.7)
          font.family: root.fontFamily
          font.pixelSize: 12
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }

    BracketedFrame {
      sectionIndex: 3
      sectionLabel: "SCALING"
      sectionMeta: (sc.monitorName || "monitor") + "  ·  Super+= cycles up, Super+- cycles down"

      Row {
        spacing: 14

        Repeater {
          model: ["1", "1.25", "1.6", "2", "3", "4"]
          delegate: BracketChip {
            required property var modelData
            label: modelData + "×"
            selected: sc.monitorScale === modelData
            onClicked: sc.runStyle("omarchy-hyprland-monitor-scaling-set " + modelData)
          }
        }
      }
    }

    BracketedFrame {
      sectionIndex: 4
      sectionLabel: "FONT"
      sectionMeta: (sc.fontName || "—") + "  ·  " + sc.fontsList.length + " installed Nerd Fonts"

      Repeater {
        model: sc.fontsList
        delegate: FontPickerRow {
          required property var modelData
          required property int index
          width: parent.width
          rowIndex: index
          fontFamilyName: modelData
          selected: modelData === sc.fontName
          onChosen: sc.runStyle("omarchy-font-set \"" + modelData + "\"")
        }
      }
    }
  }

  // ===================== system category ===================================
  component SystemCategory: ColumnLayout {
    id: syc
    spacing: 14

    property string powerProfile: ""
    property var powerProfiles: []
    property bool nightlightOn: false
    property bool dndOn: false
    property bool idleOn: false
    property bool screensaverOn: false
    property bool suspendAvailable: true
    property int refreshTick: 0

    // Total + on-count for the BEHAVIOR section meta.
    readonly property var behaviorFlags: [
      syc.nightlightOn, !syc.dndOn, syc.idleOn, syc.screensaverOn, syc.suspendAvailable
    ]
    readonly property int behaviorOn: {
      var n = 0
      for (var i = 0; i < behaviorFlags.length; i++) if (behaviorFlags[i]) n++
      return n
    }
    readonly property int behaviorTotal: behaviorFlags.length

    function refresh() {
      refreshTick++
      readPowerProc.running = true
      readPowerListProc.running = true
      readNightlightProc.running = true
      readDndProc.running = true
      readIdleProc.running = true
      readScreensaverProc.running = true
      readSuspendProc.running = true
    }

    Process { id: applySystemProc; onExited: syc.refresh() }

    Process {
      id: readPowerProc
      command: ["bash", "-lc", "powerprofilesctl get 2>/dev/null"]
      stdout: SplitParser { onRead: function(line) { syc.powerProfile = String(line).trim() } }
    }
    Process {
      id: readPowerListProc
      command: ["bash", "-lc", "omarchy-powerprofiles-list 2>/dev/null"]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: syc.powerProfiles = String(text || "").trim().split("\n").filter(function(x) { return x.length > 0 })
      }
    }
    Process {
      id: readNightlightProc
      command: ["bash", "-lc", "hyprctl hyprsunset temperature 2>/dev/null | grep -oE '[0-9]+' | head -n1 || echo 6000"]
      stdout: SplitParser { onRead: function(line) {
        var n = parseInt(String(line).trim(), 10)
        syc.nightlightOn = isFinite(n) && n < 5500
      } }
    }
    Process {
      id: readDndProc
      command: ["bash", "-lc", "omarchy-shell-ipc notifications isDnd 2>/dev/null || echo off"]
      stdout: SplitParser { onRead: function(line) { syc.dndOn = String(line).trim() === "on" } }
    }
    Process {
      id: readIdleProc
      command: ["bash", "-lc", "pgrep -x hypridle >/dev/null && echo yes || echo no"]
      stdout: SplitParser { onRead: function(line) { syc.idleOn = String(line).trim() === "yes" } }
    }
    Process {
      id: readScreensaverProc
      command: ["bash", "-lc", "[[ -f $HOME/.local/state/omarchy/toggles/screensaver-off ]] && echo no || echo yes"]
      stdout: SplitParser { onRead: function(line) { syc.screensaverOn = String(line).trim() === "yes" } }
    }
    Process {
      id: readSuspendProc
      command: ["bash", "-lc", "[[ -f $HOME/.local/state/omarchy/toggles/suspend-off ]] && echo no || echo yes"]
      stdout: SplitParser { onRead: function(line) { syc.suspendAvailable = String(line).trim() === "yes" } }
    }

    function runSystem(cmd) {
      applySystemProc.command = ["bash", "-lc", cmd]
      applySystemProc.running = true
    }

    // Catch external state changes (CLI / menu / power-profile daemon).
    FileView {
      path: root.home + "/.local/state/omarchy/toggles"
      watchChanges: true
      printErrors: false
      onFileChanged: syc.refresh()
    }

    Component.onCompleted: refresh()
    onVisibleChanged: if (visible) refresh()

    BracketedFrame {
      sectionIndex: 1
      sectionLabel: "POWER PROFILE"
      sectionMeta: "power-profiles-daemon"

      Row {
        spacing: 14

        Repeater {
          model: syc.powerProfiles
          delegate: BracketChip {
            required property var modelData
            label: modelData.charAt(0).toUpperCase() + modelData.slice(1).replace("-", " ")
            selected: syc.powerProfile === modelData
            onClicked: syc.runSystem("powerprofilesctl set " + modelData)
          }
        }
      }

      Item { width: 1; height: 4 }

      Text {
        text: "CPU clocks down aggressively on saver. Performance disables boost throttling."
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: 12
        wrapMode: Text.WordWrap
        width: parent.width
      }
    }

    BracketedFrame {
      sectionIndex: 2
      sectionLabel: "BEHAVIOR"
      sectionMeta: syc.behaviorOn + "/" + syc.behaviorTotal + " enabled"

      NumberedToggleRow {
        width: parent.width
        rowIndex: 0
        label: "Nightlight"
        description: "Lower screen colour temperature in the evening."
        isOn: syc.nightlightOn
        onToggle: syc.runSystem("omarchy-toggle-nightlight")
      }
      NumberedToggleRow {
        width: parent.width
        rowIndex: 1
        label: "Notifications"
        description: syc.dndOn ? "Do-not-disturb is on — notifications are silenced." : "Notifications post normally."
        isOn: !syc.dndOn
        onToggle: syc.runSystem("omarchy-toggle-notification-silencing")
      }
      NumberedToggleRow {
        width: parent.width
        rowIndex: 2
        label: "Idle locking"
        description: "Lock the screen when idle (hypridle)."
        isOn: syc.idleOn
        onToggle: syc.runSystem("omarchy-toggle-idle")
      }
      NumberedToggleRow {
        width: parent.width
        rowIndex: 3
        label: "Screensaver"
        description: "Allow the screensaver to engage during idle."
        isOn: syc.screensaverOn
        onToggle: syc.runSystem("omarchy-toggle-screensaver")
      }
      NumberedToggleRow {
        width: parent.width
        rowIndex: 4
        label: "Suspend in menu"
        description: "Show 'Suspend' in the system power menu."
        isOn: syc.suspendAvailable
        onToggle: syc.runSystem("omarchy-toggle-suspend")
      }
    }
  }

  // ===================== shared chrome =====================================
  component ActionPill: Rectangle {
    id: pill
    property string text: ""
    property color foreground: root.foreground
    property bool bordered: true
    signal clicked()

    activeFocusOnTab: true
    Keys.onReturnPressed: pill.clicked()
    Keys.onEnterPressed: pill.clicked()
    Keys.onSpacePressed: pill.clicked()

    implicitWidth: pillLabel.implicitWidth + 22
    implicitHeight: 26
    radius: root.cornerRadius
    color: pill.activeFocus
      ? root.focusFillColor
      : (pillArea.containsMouse ? Qt.rgba(pill.foreground.r, pill.foreground.g, pill.foreground.b, 0.15) : "transparent")
    border.color: pill.activeFocus ? root.focusBorderColor : (pill.bordered ? pill.foreground : "transparent")
    border.width: pill.activeFocus ? root.focusBorderWidth : 1

    Behavior on color { ColorAnimation { duration: 100 } }

    Text {
      id: pillLabel
      anchors.centerIn: parent
      text: pill.text
      color: pill.foreground
      font.family: root.fontFamily
      font.pixelSize: 12
    }

    MouseArea {
      id: pillArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pill.clicked()
    }
  }

  component IconButton: Rectangle {
    id: iconButton
    property string glyph: ""
    property string tooltip: ""
    property color foreground: root.foreground
    signal clicked()

    activeFocusOnTab: true
    Keys.onReturnPressed: iconButton.clicked()
    Keys.onEnterPressed: iconButton.clicked()
    Keys.onSpacePressed: iconButton.clicked()

    implicitWidth: 26
    implicitHeight: 26
    radius: root.cornerRadius
    color: iconButton.activeFocus
      ? root.focusFillColor
      : (iconArea.containsMouse ? Qt.rgba(iconButton.foreground.r, iconButton.foreground.g, iconButton.foreground.b, 0.18) : "transparent")
    border.color: iconButton.activeFocus ? root.focusBorderColor : "transparent"
    border.width: iconButton.activeFocus ? root.focusBorderWidth : 0

    Behavior on color { ColorAnimation { duration: 100 } }

    Text {
      anchors.centerIn: parent
      text: iconButton.glyph
      color: iconButton.foreground
      font.family: root.fontFamily
      font.pixelSize: 14
    }

    MouseArea {
      id: iconArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: iconButton.clicked()
    }
  }

  // Bracketed frame with a notched `[N] LABEL · meta` title — identical
  // chrome to SectionEditor / RadioSelector, factored out for the
  // non-bar categories. Inner children go into the default `inner` slot.
  component BracketedFrame: Item {
    id: bf
    property string sectionLabel: ""
    property string sectionMeta: ""
    property int sectionIndex: 0
    default property alias inner: bfInner.data
    readonly property int notchH: 16

    Layout.fillWidth: true
    implicitHeight: notchH / 2 + bfInner.implicitHeight + 28

    Rectangle {
      id: bfFrame
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: bf.notchH / 2
      anchors.bottom: parent.bottom
      color: "transparent"
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)
      border.width: 1
      radius: root.cornerRadius
    }

    Rectangle {
      anchors.left: parent.left
      anchors.leftMargin: 18
      anchors.top: parent.top
      width: bfLabel.implicitWidth + 16
      height: bf.notchH
      color: root.background

      Text {
        id: bfLabel
        anchors.centerIn: parent
        text: "[" + bf.sectionIndex + "] " + bf.sectionLabel
              + (bf.sectionMeta !== "" ? "  ·  " + bf.sectionMeta : "")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 12
      }
    }

    Column {
      id: bfInner
      anchors.left: bfFrame.left
      anchors.right: bfFrame.right
      anchors.top: bfFrame.top
      anchors.leftMargin: 14
      anchors.rightMargin: 14
      anchors.topMargin: 14
      spacing: 2
    }
  }

  // Numbered toggle row — `▶ NN  Label   Description       [x]` / `[ ]`.
  // Focusable; Enter / Space / click flips the state.
  component NumberedToggleRow: Item {
    id: tog
    property int rowIndex: 0
    property string label: ""
    property string description: ""
    property bool isOn: false
    signal toggle()

    implicitHeight: 28
    activeFocusOnTab: true

    onActiveFocusChanged: {
      if (activeFocus) {
        root.selectedSection = ""
        root.selectedIndex = -1
      }
    }

    Keys.onReturnPressed: tog.toggle()
    Keys.onEnterPressed:  tog.toggle()
    Keys.onSpacePressed:  tog.toggle()

    Rectangle {
      anchors.fill: parent
      color: tog.activeFocus
        ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
        : (togArea.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05) : "transparent")
      radius: root.cornerRadius
      Behavior on color { ColorAnimation { duration: 80 } }
    }

    Text {
      text: tog.activeFocus ? "▶" : ""
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: 11
      anchors.left: parent.left
      anchors.leftMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      width: 12
    }

    Text {
      text: root.padTwo(tog.rowIndex + 1)
      color: Qt.darker(root.foreground, 1.9)
      font.family: root.fontFamily
      font.pixelSize: 12
      anchors.left: parent.left
      anchors.leftMargin: 24
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: togLabel
      text: tog.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: 13
      font.bold: tog.activeFocus || tog.isOn
      anchors.left: parent.left
      anchors.leftMargin: 56
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      text: tog.description
      color: Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: 12
      anchors.left: togLabel.right
      anchors.leftMargin: 14
      anchors.right: togState.left
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
    }

    Text {
      id: togState
      text: tog.isOn ? "[x]" : "[ ]"
      color: tog.isOn ? root.accent : Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: 13
      font.bold: tog.isOn
      anchors.right: parent.right
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      id: togArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: { tog.forceActiveFocus(); tog.toggle() }
    }
  }

  // Numbered radio row — `▶ NN  ( )  Label   detail        trailing`.
  // `trailing` lets each call site stamp a status string ("default",
  // "not installed", "loaded", etc.) in its own color.
  component NumberedRadioRow: Item {
    id: nr
    property int rowIndex: 0
    property string label: ""
    property string detail: ""
    property string description: ""
    property string trailing: ""
    property color trailingColor: root.accent
    property bool selected: false
    property bool available: true
    property bool emphasizeDetail: false
    signal chosen()

    implicitHeight: 28
    activeFocusOnTab: nr.available
    opacity: nr.available ? 1 : 0.45

    onActiveFocusChanged: {
      if (activeFocus) {
        root.selectedSection = ""
        root.selectedIndex = -1
      }
    }

    Keys.onReturnPressed: if (nr.available && !nr.selected) nr.chosen()
    Keys.onEnterPressed:  if (nr.available && !nr.selected) nr.chosen()
    Keys.onSpacePressed:  if (nr.available && !nr.selected) nr.chosen()

    Rectangle {
      anchors.fill: parent
      color: nr.activeFocus
        ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
        : (nrArea.containsMouse && nr.available ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05) : "transparent")
      radius: root.cornerRadius
      Behavior on color { ColorAnimation { duration: 80 } }
    }

    Text {
      text: nr.activeFocus ? "▶" : ""
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: 11
      anchors.left: parent.left
      anchors.leftMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      width: 12
    }

    Text {
      text: root.padTwo(nr.rowIndex + 1)
      color: Qt.darker(root.foreground, 1.9)
      font.family: root.fontFamily
      font.pixelSize: 12
      anchors.left: parent.left
      anchors.leftMargin: 24
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: nrRadio
      text: nr.selected ? "(●)" : "( )"
      color: nr.selected ? root.accent : Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: 12
      anchors.left: parent.left
      anchors.leftMargin: 52
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: nrLabel
      text: nr.label
      color: nr.selected ? root.foreground : Qt.darker(root.foreground, 1.15)
      font.family: root.fontFamily
      font.pixelSize: 13
      font.bold: nr.selected || nr.activeFocus
      anchors.left: nrRadio.right
      anchors.leftMargin: 10
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: nrDetail
      text: nr.detail
      color: nr.emphasizeDetail
        ? Qt.darker(root.foreground, 1.3)
        : Qt.darker(root.foreground, 1.7)
      font.family: root.fontFamily
      font.pixelSize: 12
      font.italic: nr.emphasizeDetail
      anchors.left: nrLabel.right
      anchors.leftMargin: 14
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      text: nr.description
      color: Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: 12
      anchors.left: nrDetail.right
      anchors.leftMargin: 14
      anchors.right: nrTrail.left
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
    }

    Text {
      id: nrTrail
      text: nr.trailing
      color: nr.trailingColor
      font.family: root.fontFamily
      font.pixelSize: 12
      font.bold: nr.selected
      anchors.right: parent.right
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      id: nrArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: nr.available ? Qt.PointingHandCursor : Qt.ForbiddenCursor
      onClicked: if (nr.available && !nr.selected) { nr.forceActiveFocus(); nr.chosen() }
    }
  }

  // Numbered font picker row — like NumberedRadioRow but the label and a
  // short sample render in the font itself so the user can preview each
  // typeface. No trailing status; selection is implicit via accent color.
  component FontPickerRow: Item {
    id: fpr
    property int rowIndex: 0
    property string fontFamilyName: ""
    property bool selected: false
    signal chosen()

    implicitHeight: 30
    activeFocusOnTab: true

    onActiveFocusChanged: {
      if (activeFocus) {
        root.selectedSection = ""
        root.selectedIndex = -1
      }
    }

    Keys.onReturnPressed: if (!fpr.selected) fpr.chosen()
    Keys.onEnterPressed:  if (!fpr.selected) fpr.chosen()
    Keys.onSpacePressed:  if (!fpr.selected) fpr.chosen()

    Rectangle {
      anchors.fill: parent
      color: fpr.activeFocus
        ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
        : (fprArea.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05) : "transparent")
      radius: root.cornerRadius
      Behavior on color { ColorAnimation { duration: 80 } }
    }

    Text {
      text: fpr.activeFocus ? "▶" : ""
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: 11
      anchors.left: parent.left
      anchors.leftMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      width: 12
    }

    Text {
      text: root.padTwo(fpr.rowIndex + 1)
      color: Qt.darker(root.foreground, 1.9)
      font.family: root.fontFamily
      font.pixelSize: 12
      anchors.left: parent.left
      anchors.leftMargin: 24
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: fprRadio
      text: fpr.selected ? "(●)" : "( )"
      color: fpr.selected ? root.accent : Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: 12
      anchors.left: parent.left
      anchors.leftMargin: 52
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: fprName
      text: fpr.fontFamilyName
      color: fpr.selected ? root.accent : root.foreground
      font.family: fpr.fontFamilyName
      font.pixelSize: 13
      font.bold: fpr.selected
      anchors.left: fprRadio.right
      anchors.leftMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      width: 230
    }

    Text {
      text: "The quick brown fox 0123"
      color: Qt.darker(root.foreground, 1.4)
      font.family: fpr.fontFamilyName
      font.pixelSize: 12
      anchors.right: parent.right
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
    }

    MouseArea {
      id: fprArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: if (!fpr.selected) { fpr.forceActiveFocus(); fpr.chosen() }
    }
  }

  // Inline chip — `[Label]` when selected, ` Label ` otherwise. Used for
  // chip rows (corners / scaling / power profile).
  component BracketChip: Item {
    id: bc
    property string label: ""
    property bool selected: false
    signal clicked()

    activeFocusOnTab: true

    onActiveFocusChanged: {
      if (activeFocus) {
        root.selectedSection = ""
        root.selectedIndex = -1
      }
    }

    Keys.onReturnPressed: bc.clicked()
    Keys.onEnterPressed:  bc.clicked()
    Keys.onSpacePressed:  bc.clicked()

    implicitWidth: bcLabel.implicitWidth + 14
    implicitHeight: 24

    Rectangle {
      anchors.fill: parent
      color: bc.activeFocus
        ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
        : (bcArea.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05) : "transparent")
      radius: root.cornerRadius
      Behavior on color { ColorAnimation { duration: 80 } }
    }

    Text {
      id: bcLabel
      anchors.centerIn: parent
      text: bc.selected ? "[" + bc.label + "]" : bc.label
      color: bc.selected ? root.accent : Qt.darker(root.foreground, 1.1)
      font.family: root.fontFamily
      font.pixelSize: 13
      font.bold: bc.selected
    }

    MouseArea {
      id: bcArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: { bc.forceActiveFocus(); bc.clicked() }
    }
  }

  // ===================== bar layout pieces =================================
  // Bracketed-frame section. The title and "+ Add" affordance are notched
  // into the top border line; the inner column holds the widget rows.
  component SectionEditor: Item {
    id: section

    property string sectionKey: ""
    property string sectionLabel: ""
    property int sectionIndex: 0
    property var entries: root.sectionArray(section.sectionKey)
    // Top inset: room for the notched label to sit half-above the frame.
    readonly property int notchH: 16

    Layout.fillWidth: true
    implicitHeight: section.notchH / 2 + innerColumn.implicitHeight + 26

    Connections {
      target: root
      function onDraftRevisionChanged() { section.entries = root.sectionArray(section.sectionKey) }
    }

    // The frame itself. Starts below the notch line so the label can punch
    // through the top border cleanly.
    Rectangle {
      id: sectionFrame
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: section.notchH / 2
      anchors.bottom: parent.bottom
      color: "transparent"
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)
      border.width: 1
      radius: root.cornerRadius
    }

    // Left notch: "[N] Bar · Section · K widgets"
    Rectangle {
      anchors.left: parent.left
      anchors.leftMargin: 18
      anchors.top: parent.top
      width: sectionLabel.implicitWidth + 16
      height: section.notchH
      color: root.background

      Text {
        id: sectionLabel
        anchors.centerIn: parent
        text: "[" + section.sectionIndex + "] " + section.sectionLabel
              + "  ·  " + section.entries.length
              + (section.entries.length === 1 ? " widget" : " widgets")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 12
      }
    }

    // Add-widget popup. Anchored under the "+ Add widget" placeholder row
    // at the bottom of the section (see innerColumn below). Pulls fresh
    // availability data each time it opens.
    Popup {
      id: addPopup
      parent: addRow
      x: 0
      y: addRow.height + 4
      width: Math.max(300, section.width - 28)
      implicitHeight: Math.min(addList.contentHeight + 2, 340)
      padding: 1
      modal: false
      focus: true

      background: Rectangle {
        color: root.background
        border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.7)
        border.width: 1
        radius: root.cornerRadius
      }

      contentItem: ListView {
        id: addList
        clip: true
        model: root.availableToAdd(section.sectionKey)
        boundsBehavior: Flickable.StopAtBounds

        delegate: Rectangle {
          required property var modelData
          width: addList.width
          height: 38
          color: addArea.containsMouse
            ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
            : "transparent"

          Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
              text: modelData.name
                + (modelData.isNoctalia ? "  (Noctalia)" : "")
                + (modelData.elsewhere ? "  (elsewhere)" : "")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              elide: Text.ElideRight
              width: parent.width
            }
            Text {
              visible: text !== ""
              text: modelData.description || ""
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 11
              elide: Text.ElideRight
              width: parent.width
            }
          }

          MouseArea {
            id: addArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.addEntry(section.sectionKey, modelData.id)
              addPopup.close()
            }
          }
        }
      }
    }

    // Interior rows + the trailing "+ Add widget" placeholder.
    Column {
      id: innerColumn
      anchors.left: sectionFrame.left
      anchors.right: sectionFrame.right
      anchors.top: sectionFrame.top
      anchors.leftMargin: 14
      anchors.rightMargin: 14
      anchors.topMargin: 14
      spacing: 2

      Repeater {
        model: section.entries
        delegate: WidgetRow {
          required property var modelData
          required property int index
          width: innerColumn.width
          sectionKey: section.sectionKey
          entryIndex: index
          entry: modelData
        }
      }

      // Placeholder "+ Add widget" row. Looks like a widget row but dimmer.
      // Number prefix continues the section's sequence so the eye reads it as
      // "this is where the next widget would land". Also accepts mouse-drag
      // drops as an "append to this section" target — important for empty
      // sections where there's no row to drop on.
      Item {
        id: addRow
        width: innerColumn.width
        height: 26
        activeFocusOnTab: true

        // True while a foreign widget is being dragged over this row, so we
        // can render the insertion-line cue.
        property bool dropActive: false

        // Clear bar-row selection when this placeholder takes focus, so that
        // dd / J/K / 1-3 don't accidentally act on the previous widget.
        onActiveFocusChanged: {
          if (activeFocus) {
            root.selectedSection = ""
            root.selectedIndex = -1
          }
        }

        Keys.onReturnPressed: addPopup.open()
        Keys.onEnterPressed: addPopup.open()
        Keys.onSpacePressed: addPopup.open()

        Rectangle {
          anchors.fill: parent
          color: addRow.activeFocus
            ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10)
            : (addArea.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05) : "transparent")
          radius: root.cornerRadius
          Behavior on color { ColorAnimation { duration: 80 } }
        }

        // Insertion-line cue while a widget is hovered over this row. Drawn
        // at the top because the drop lands "above" the placeholder — i.e.
        // appended to the section's last real widget.
        Rectangle {
          visible: addRow.dropActive
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: 2
          color: root.accent
          z: 10
        }

        Text {
          text: addRow.activeFocus ? "▶" : ""
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: 11
          anchors.left: parent.left
          anchors.leftMargin: 6
          anchors.verticalCenter: parent.verticalCenter
          width: 12
        }

        Text {
          text: root.padTwo(section.entries.length + 1)
          color: Qt.darker(root.foreground, 1.9)
          font.family: root.fontFamily
          font.pixelSize: 12
          anchors.left: parent.left
          anchors.leftMargin: 24
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          text: "+ Add widget"
          color: addArea.containsMouse || addRow.activeFocus
            ? root.accent
            : Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: 13
          font.italic: true
          anchors.left: parent.left
          anchors.leftMargin: 56
          anchors.verticalCenter: parent.verticalCenter
          Behavior on color { ColorAnimation { duration: 80 } }
        }

        MouseArea {
          id: addArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { addRow.forceActiveFocus(); addPopup.open() }
        }

        DropArea {
          anchors.fill: parent
          keys: ["omarchy-bar-widget"]

          onEntered: (drag) => {
            if (!drag.source
                || drag.source.sourceSection === undefined
                || drag.source.sourceIndex === undefined) {
              addRow.dropActive = false
              return
            }
            addRow.dropActive = true
          }
          onExited: addRow.dropActive = false

          onDropped: (drop) => {
            addRow.dropActive = false
            if (!drop.source
                || drop.source.sourceSection === undefined
                || drop.source.sourceIndex === undefined) {
              drop.accepted = false
              return
            }
            // Append to the end of this section.
            root.dropWidget(drop.source.sourceSection, drop.source.sourceIndex,
                            section.sectionKey, section.entries.length)
            drop.accept(Qt.MoveAction)
          }
        }
      }
    }
  }

  // Bracketed radio-selector — same frame chrome as SectionEditor, but the
  // body is a list of `( ) / (●)` options instead of widget rows. Used for
  // Position / Center anchor (and any future single-choice setting).
  component RadioSelector: Item {
    id: rs

    property string sectionLabel: ""
    property string sectionMeta: ""
    property int sectionIndex: 0
    property var options: []
    property string value: ""
    signal changed(string newValue)

    readonly property int notchH: 16

    Layout.fillWidth: true
    implicitHeight: rs.notchH / 2 + rsInner.implicitHeight + 26

    // Frame — identical to SectionEditor's so the two read as siblings.
    Rectangle {
      id: rsFrame
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: rs.notchH / 2
      anchors.bottom: parent.bottom
      color: "transparent"
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)
      border.width: 1
      radius: root.cornerRadius
    }

    // Left notch label: "[N] LABEL · meta"
    Rectangle {
      anchors.left: parent.left
      anchors.leftMargin: 18
      anchors.top: parent.top
      width: rsLabel.implicitWidth + 16
      height: rs.notchH
      color: root.background

      Text {
        id: rsLabel
        anchors.centerIn: parent
        text: "[" + rs.sectionIndex + "] " + rs.sectionLabel
              + (rs.sectionMeta !== "" ? "  ·  " + rs.sectionMeta : "")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 12
      }
    }

    Column {
      id: rsInner
      anchors.left: rsFrame.left
      anchors.right: rsFrame.right
      anchors.top: rsFrame.top
      anchors.leftMargin: 14
      anchors.rightMargin: 14
      anchors.topMargin: 14
      spacing: 2

      Repeater {
        model: rs.options
        delegate: RadioOption {
          required property var modelData
          required property int index
          width: rsInner.width
          optionData: modelData
          optionIndex: index
          selected: rs.value === modelData.value
          onChosen: rs.changed(modelData.value)
        }
      }
    }
  }

  // One row inside a RadioSelector. `( )` for unselected, `(●)` for the
  // currently-applied option. Focusable; Enter / Space / click commits.
  component RadioOption: Item {
    id: opt
    property var optionData: ({})
    property int optionIndex: 0
    property bool selected: false
    signal chosen()

    implicitHeight: 26
    activeFocusOnTab: true

    // When focused, this isn't a "widget" the dd/J/K/1-3 bindings apply to,
    // so clear the bar-row selection just like the Add-widget placeholder.
    onActiveFocusChanged: {
      if (activeFocus) {
        root.selectedSection = ""
        root.selectedIndex = -1
      }
    }

    Keys.onReturnPressed: opt.chosen()
    Keys.onEnterPressed:  opt.chosen()
    Keys.onSpacePressed:  opt.chosen()

    Rectangle {
      anchors.fill: parent
      color: opt.activeFocus
        ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
        : (optArea.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05) : "transparent")
      radius: root.cornerRadius
      Behavior on color { ColorAnimation { duration: 80 } }
    }

    Text {
      text: opt.activeFocus ? "▶" : ""
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: 11
      anchors.left: parent.left
      anchors.leftMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      width: 12
    }

    Text {
      text: root.padTwo(opt.optionIndex + 1)
      color: Qt.darker(root.foreground, 1.9)
      font.family: root.fontFamily
      font.pixelSize: 12
      anchors.left: parent.left
      anchors.leftMargin: 24
      anchors.verticalCenter: parent.verticalCenter
    }

    // Radio circle — accent-tinted when selected.
    Text {
      id: radio
      text: opt.selected ? "(●)" : "( )"
      color: opt.selected ? root.accent : Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: 12
      anchors.left: parent.left
      anchors.leftMargin: 52
      anchors.verticalCenter: parent.verticalCenter
    }

    // Option label.
    Text {
      id: optLabel
      text: opt.optionData.label || opt.optionData.value || ""
      color: opt.selected ? root.foreground : Qt.darker(root.foreground, 1.15)
      font.family: root.fontFamily
      font.pixelSize: 13
      font.bold: opt.selected || opt.activeFocus
      anchors.left: radio.right
      anchors.leftMargin: 10
      anchors.verticalCenter: parent.verticalCenter
    }

    // Inline description.
    Text {
      text: opt.optionData.description || ""
      color: Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: 12
      anchors.left: optLabel.right
      anchors.leftMargin: 14
      anchors.right: appliedLabel.left
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
    }

    // Trailing status — only the currently-selected option shows "applied".
    Text {
      id: appliedLabel
      visible: opt.selected
      text: "applied"
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: 12
      anchors.right: parent.right
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      id: optArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: { opt.forceActiveFocus(); opt.chosen() }
    }
  }

  // A single widget row inside a section frame. Numbered prefix on the left,
  // name + description in the middle, [↕] [⚙] [×] action chips on the right.
  // Focusable: when focused, marks itself as the "selected" widget so the
  // modeline + section header reflect it, and the J/K/1-3/dd shortcuts act
  // on it. Also draggable: press-and-drag past a small threshold begins a
  // mouse reorder; insertion is shown as a thin accent line on the target
  // row (above/below cursor midpoint) or the "+ Add widget" placeholder.
  component WidgetRow: Item {
    id: row
    property string sectionKey: ""
    property int entryIndex: -1
    property var entry: ({})
    readonly property string entryId: entry && entry.id ? String(entry.id) : ""
    readonly property string displayName: root.widgetName(entryId)
    readonly property string description: root.widgetDescription(entryId)
    readonly property bool hasSettings: root.widgetHasSettings(entryId)
    // Marker so refocusSelected() can pick rows out of the focusables list
    // without false-matching unrelated controls.
    readonly property bool barRowMarker: true

    // Drag-hover state used to render the insertion line. -1 = above this
    // row, 1 = below this row, 0 = no drop hover. Always 0 on the source row
    // of an in-flight drag.
    property int dropHoverSide: 0

    // True when this row IS the one being dragged via the shared dragGhost.
    // Used to dim the source slot so the floating chip is the visual anchor.
    readonly property bool isDragSource: dragGhost.Drag.active
                                         && dragGhost.sourceSection === row.sectionKey
                                         && dragGhost.sourceIndex === row.entryIndex

    implicitHeight: 26
    activeFocusOnTab: true
    opacity: row.isDragSource ? 0.35 : 1.0
    Behavior on opacity { NumberAnimation { duration: 90 } }

    onActiveFocusChanged: {
      if (activeFocus) {
        root.selectedSection = row.sectionKey
        root.selectedIndex = row.entryIndex
      }
    }

    Keys.onReturnPressed: if (row.hasSettings) settingsLoader.open(row.entry)
    Keys.onEnterPressed:  if (row.hasSettings) settingsLoader.open(row.entry)

    // Selection background. Subtle accent tint when focused; light hover
    // tint otherwise.
    Rectangle {
      anchors.fill: parent
      color: row.activeFocus
        ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
        : (rowArea.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05) : "transparent")
      radius: root.cornerRadius
      Behavior on color { ColorAnimation { duration: 80 } }
    }

    // Insertion-line indicators. Rendered on the row being hovered as a
    // drop target — never on the row being dragged (dropHoverSide is gated
    // against drag.source === row in the DropArea handlers below).
    Rectangle {
      visible: row.dropHoverSide === -1
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: 2
      color: root.accent
      z: 10
    }
    Rectangle {
      visible: row.dropHoverSide === 1
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 2
      color: root.accent
      z: 10
    }

    // ▶ selection caret. Always occupies the same column so labels don't
    // shift between focused / unfocused.
    Text {
      text: row.activeFocus ? "▶" : ""
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: 11
      anchors.left: parent.left
      anchors.leftMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      width: 12
    }

    // Numeric prefix (01, 02, ...) — vim-style line numbers.
    Text {
      id: numberLabel
      text: root.padTwo(row.entryIndex + 1)
      color: Qt.darker(root.foreground, 1.8)
      font.family: root.fontFamily
      font.pixelSize: 12
      anchors.left: parent.left
      anchors.leftMargin: 24
      anchors.verticalCenter: parent.verticalCenter
    }

    // Widget display name.
    Text {
      id: nameLabel
      text: row.displayName
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: 13
      font.bold: row.activeFocus
      anchors.left: parent.left
      anchors.leftMargin: 56
      anchors.verticalCenter: parent.verticalCenter
    }

    // Inline description.
    Text {
      text: row.description
      color: Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: 12
      anchors.left: nameLabel.right
      anchors.leftMargin: 14
      anchors.right: actionRow.left
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
    }

    // Action chips: [ ↕ ] reorder · [ * ] settings · [ × ] remove. Bracket
    // colors track each chip's glyph color so the whole chip reads as one
    // semantic unit. Mouse users get a click affordance on each chip.
    Row {
      id: actionRow
      anchors.right: parent.right
      anchors.rightMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8

      BracketIcon {
        glyph: "↕"
        tooltip: "Move down (or J/K to reorder)"
        foreground: Qt.darker(root.foreground, 1.25)
        onClicked: {
          var arr = root.sectionArray(row.sectionKey)
          var next = (row.entryIndex + 1) % arr.length
          if (next !== row.entryIndex) {
            root.selectedSection = row.sectionKey
            root.selectedIndex = row.entryIndex
            root.moveEntry(row.sectionKey, row.entryIndex, next)
            root.selectedIndex = next
            Qt.callLater(root.refocusSelected)
          }
        }
      }
      BracketIcon {
        glyph: "*"
        tooltip: "Widget settings"
        foreground: root.accent
        visible: row.hasSettings
        // Reserve space when invisible so the × column doesn't shift.
        opacity: row.hasSettings ? 1 : 0
        enabled: row.hasSettings
        onClicked: settingsLoader.open(row.entry)
      }
      BracketIcon {
        glyph: "×"
        tooltip: "Remove (or dd)"
        foreground: root.urgent
        onClicked: root.removeEntry(row.sectionKey, row.entryIndex)
      }
    }

    MouseArea {
      id: rowArea
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton
      cursorShape: rowArea.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

      // Press position cached so we only flip into drag mode once the
      // cursor has moved past a small threshold — keeps clicks distinct
      // from drags so the row still focuses on a stationary press.
      property real pressX: 0
      property real pressY: 0
      property bool dragging: false

      // Reposition the shared ghost in panelContent-local coords so the
      // chip tracks the cursor across every section (DropArea events fire
      // off the dragged item's scene position, not the cursor's).
      function moveGhostToMouse(mouse) {
        var p = rowArea.mapToItem(panelContent, mouse.x, mouse.y)
        dragGhost.x = p.x - dragGhost.width / 2
        dragGhost.y = p.y - dragGhost.height / 2
      }

      onPressed: (mouse) => {
        rowArea.pressX = mouse.x
        rowArea.pressY = mouse.y
        rowArea.dragging = false
        row.forceActiveFocus()
      }

      onPositionChanged: (mouse) => {
        if (!rowArea.pressed) return
        if (!rowArea.dragging) {
          if (Math.abs(mouse.x - rowArea.pressX) > 6
              || Math.abs(mouse.y - rowArea.pressY) > 6) {
            rowArea.dragging = true
            dragGhost.sourceSection = row.sectionKey
            dragGhost.sourceIndex = row.entryIndex
            dragGhost.sourceName = row.displayName
            rowArea.moveGhostToMouse(mouse)
            dragGhost.Drag.start()
          }
        } else {
          rowArea.moveGhostToMouse(mouse)
        }
      }

      onReleased: {
        if (!rowArea.dragging) return
        // Commit to whichever DropArea is under the cursor; if none,
        // Drag.drop() is a no-op and the layout is unchanged. The ghost's
        // visibility unbinds from Drag.active so the chip clears itself.
        dragGhost.Drag.drop()
        rowArea.dragging = false
      }

      onCanceled: {
        if (!rowArea.dragging) return
        dragGhost.Drag.cancel()
        rowArea.dragging = false
      }

      onClicked: if (!rowArea.dragging) row.forceActiveFocus()
    }

    // Accepts drops from the dragGhost chip. The insertion side is decided
    // by cursor Y relative to the row's midpoint, surfaced as `dropHoverSide`
    // so the insertion line renders above or below. Skipped when this row
    // is the drag source (dropping onto yourself is a no-op).
    DropArea {
      anchors.fill: parent
      keys: ["omarchy-bar-widget"]

      function isOwnSource(drag) {
        return drag && drag.source
            && drag.source.sourceSection === row.sectionKey
            && drag.source.sourceIndex === row.entryIndex
      }

      onEntered: (drag) => {
        if (isOwnSource(drag)) { row.dropHoverSide = 0; return }
        row.dropHoverSide = drag.y < row.height / 2 ? -1 : 1
      }

      onPositionChanged: (drag) => {
        if (isOwnSource(drag)) { row.dropHoverSide = 0; return }
        row.dropHoverSide = drag.y < row.height / 2 ? -1 : 1
      }

      onExited: row.dropHoverSide = 0

      onDropped: (drop) => {
        var side = row.dropHoverSide
        row.dropHoverSide = 0
        if (!drop.source
            || drop.source.sourceSection === undefined
            || drop.source.sourceIndex === undefined) {
          drop.accepted = false
          return
        }
        if (drop.source.sourceSection === row.sectionKey
            && drop.source.sourceIndex === row.entryIndex) {
          drop.accepted = false
          return
        }
        var targetIdx = row.entryIndex + (side > 0 ? 1 : 0)
        root.dropWidget(drop.source.sourceSection, drop.source.sourceIndex,
                        row.sectionKey, targetIdx)
        drop.accept(Qt.MoveAction)
      }
    }

    SettingsDialog {
      id: settingsLoader
      anchorWindow: window
      sectionKey: row.sectionKey
      entryIndex: row.entryIndex
    }
  }

  // [ X ] chip — bracketed glyph button. Sized for a comfortable row of three.
  // Bracket color tracks the glyph color so the whole chip reads as a single
  // semantic unit (urgent-red for remove, accent for settings, neutral for
  // reorder). Internal padding gives `[ X ]` rather than `[X]`.
  component BracketIcon: Item {
    id: bi
    property string glyph: ""
    property string tooltip: ""
    property color foreground: root.foreground
    // Brackets dim toward the glyph color when not hovered, then brighten on
    // hover to mirror the glyph itself.
    readonly property color bracketColor: Qt.rgba(bi.foreground.r, bi.foreground.g, bi.foreground.b, 0.55)
    signal clicked()

    implicitWidth: chip.implicitWidth + 6
    implicitHeight: 22

    Row {
      id: chip
      anchors.centerIn: parent
      spacing: 5

      Text {
        text: "["
        color: biArea.containsMouse ? bi.foreground : bi.bracketColor
        font.family: root.fontFamily
        font.pixelSize: 13
        Behavior on color { ColorAnimation { duration: 80 } }
      }
      Text {
        text: bi.glyph
        color: bi.foreground
        font.family: root.fontFamily
        font.pixelSize: 13
        font.bold: biArea.containsMouse
      }
      Text {
        text: "]"
        color: biArea.containsMouse ? bi.foreground : bi.bracketColor
        font.family: root.fontFamily
        font.pixelSize: 13
        Behavior on color { ColorAnimation { duration: 80 } }
      }
    }

    MouseArea {
      id: biArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: bi.clicked()
    }
  }

  component SettingsDialog: Item {
    id: dialog
    property var anchorWindow: null
    property string sectionKey: ""
    property int entryIndex: -1
    property var workingEntry: ({})

    function open(entry) {
      workingEntry = root.cloneJson(entry)
      win.visible = true
    }

    function commit() {
      if (formLoader.item && typeof formLoader.item.saveSettings === "function") {
        formLoader.item.saveSettings()
      } else {
        root.updateEntry(sectionKey, entryIndex, workingEntry)
      }
      win.visible = false
    }

    function discard() { win.visible = false }

    function fieldChanged(key, value) {
      var copy = root.cloneJson(workingEntry)
      copy[key] = value
      workingEntry = copy
    }

    FloatingWindow {
      id: win
      title: "Widget settings — " + root.widgetName(dialog.workingEntry.id || "")
      color: root.background
      implicitWidth: 380
      implicitHeight: 320
      visible: false

      Rectangle {
        anchors.fill: parent
        color: root.background

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: 18
          spacing: 12

          Text {
            text: root.widgetName(dialog.workingEntry.id || "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 15
            font.bold: true
          }

          Text {
            text: root.widgetDescription(dialog.workingEntry.id || "")
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          Loader {
            id: formLoader
            Layout.fillWidth: true
            sourceComponent: formComponent(dialog.workingEntry.id || "")
            onLoaded: {
              if (item && "entry" in item) item.entry = dialog.workingEntry
              if (item && "fieldChanged" in item) {
                item.fieldChanged.connect(function(key, value) { dialog.fieldChanged(key, value) })
              }
            }
          }

          Item { Layout.fillHeight: true }

          Row {
            Layout.alignment: Qt.AlignRight
            spacing: 8
            ActionPill { text: "Cancel"; bordered: false; onClicked: dialog.discard() }
            ActionPill { text: "Apply"; onClicked: dialog.commit() }
          }
        }
      }
    }
  }

  // ---------------- per-widget form resolution -----------------------------
  function formComponent(id) {
    var meta = widgetMetadata(id)
    if (meta && meta.settingsForm) {
      switch (meta.settingsForm) {
      case "spacerSettings": return spacerSettingsComponent
      case "calendarSettings": return calendarSettingsComponent
      case "weatherSettings": return weatherSettingsComponent
      }
    }
    var manifest = root.pluginRegistry ? root.pluginRegistry.installedPlugins[id] : null
    if (manifest && manifest.__noctaliaCompat && manifest.entryPoints && manifest.entryPoints.settings)
      return noctaliaSettingsComponent
    if (widgetSchema(id).length > 0) return dynamicSettingsComponent
    return null
  }

  Component {
    id: dynamicSettingsComponent
    SettingsUi.DynamicSettingsForm {
      schema: root.widgetSchema(entry.id || "")
      foregroundColor: root.foreground
      fontFamilyName: root.fontFamily
    }
  }

  Component {
    id: noctaliaSettingsComponent

    Item {
      id: noctaliaForm
      property var entry: ({})
      property string pluginId: entry && entry.id ? String(entry.id) : ""
      property var manifest: pluginId && root.pluginRegistry
        ? root.pluginRegistry.installedPlugins[pluginId] : null

      function saveSettings() {
        if (settingsLoader.item && typeof settingsLoader.item.saveSettings === "function") {
          settingsLoader.item.saveSettings()
        } else {
          console.warn("Noctalia settings form has no saveSettings():", pluginId)
        }
      }

      implicitHeight: settingsLoader.item ? settingsLoader.item.implicitHeight : 0
      implicitWidth: settingsLoader.item ? settingsLoader.item.implicitWidth : 0

      Loader {
        id: settingsLoader
        anchors.fill: parent
        source: {
          if (!noctaliaForm.manifest) return ""
          return root.pluginRegistry.entryPointUrl(noctaliaForm.manifest, "settings")
        }
        asynchronous: false
        onLoaded: {
          if (!item) return
          var api = (root.shell && typeof root.shell.noctaliaPluginApiFor === "function")
            ? root.shell.noctaliaPluginApiFor(noctaliaForm.pluginId) : null
          if (api && "pluginApi" in item) item.pluginApi = api
          if ("screen" in item && root.QsWindow && root.QsWindow.window)
            item.screen = root.QsWindow.window.screen
        }
        onStatusChanged: {
          if (status === Loader.Error) {
            console.warn("noctalia Settings.qml failed for " + noctaliaForm.pluginId + ":",
              sourceComponent ? sourceComponent.errorString() : "")
          }
        }
      }
    }
  }

  Component {
    id: spacerSettingsComponent

    Column {
      id: spacerForm
      signal fieldChanged(string key, var value)
      property var entry: ({})

      spacing: 8
      width: parent ? parent.width : 0

      Text {
        text: "Size (pixels)"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: 12
      }

      SpinBox {
        from: 0
        to: 256
        value: spacerForm.entry.size !== undefined ? spacerForm.entry.size : 12
        onValueModified: spacerForm.fieldChanged("size", value)
      }
    }
  }

  Component {
    id: calendarSettingsComponent

    Column {
      id: calForm
      signal fieldChanged(string key, var value)
      property var entry: ({})

      spacing: 8
      width: parent ? parent.width : 0

      component CalendarField: TextField {
        id: calField
        property string fieldKey: ""
        font.family: root.fontFamily
        font.pixelSize: 13
        width: parent.width
        color: root.foreground
        selectionColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
        selectedTextColor: root.foreground
        placeholderTextColor: Qt.darker(root.foreground, 1.6)
        leftPadding: 10
        rightPadding: 10
        topPadding: 7
        bottomPadding: 7
        onEditingFinished: if (fieldKey) calForm.fieldChanged(fieldKey, text)
        background: Rectangle {
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
                         calField.activeFocus ? 0.08 : 0.04)
          border.color: calField.activeFocus
            ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.4)
            : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
          border.width: 1
        }
      }

      Text {
        text: "Horizontal format"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: 12
      }
      CalendarField {
        fieldKey: "format"
        text: calForm.entry.format || "dddd HH:mm"
      }

      Text {
        text: "Alternate format (click to swap)"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: 12
      }
      CalendarField {
        fieldKey: "formatAlt"
        text: calForm.entry.formatAlt || "dd MMMM 'W'ww yyyy"
      }

      Text {
        text: "Vertical format (left/right bars)"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: 12
      }
      CalendarField {
        fieldKey: "verticalFormat"
        text: calForm.entry.verticalFormat || "HH\n—\nmm"
      }
    }
  }

  Component {
    id: weatherSettingsComponent

    Column {
      id: weatherForm
      signal fieldChanged(string key, var value)
      property var entry: ({})

      spacing: 8
      width: parent ? parent.width : 0

      Text {
        text: "Auto-refresh interval (minutes)"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: 12
      }

      SpinBox {
        from: 1
        to: 1440
        value: weatherForm.entry.refreshMinutes !== undefined ? weatherForm.entry.refreshMinutes : 15
        onValueModified: weatherForm.fieldChanged("refreshMinutes", value)
      }
    }
  }

  // ===================== plugins category ==================================
  component PluginManager: ColumnLayout {
    id: pm

    property int registryRevision: root.pluginRegistry ? root.pluginRegistry.registryRevision : 0
    Connections {
      target: root.pluginRegistry
      function onPluginsChanged() { pm.registryRevision = root.pluginRegistry.registryRevision }
    }

    function pluginList() {
      var rev = pm.registryRevision
      if (!root.pluginRegistry) return []
      var plugins = root.pluginRegistry.installedPlugins
      var ids = Object.keys(plugins).sort(function(a, b) {
        var fa = !!plugins[a].__isFirstParty, fb = !!plugins[b].__isFirstParty
        if (fa !== fb) return fa ? -1 : 1
        return String(plugins[a].name || a).localeCompare(String(plugins[b].name || b))
      })
      var rows = []
      for (var i = 0; i < ids.length; i++) {
        var id = ids[i]
        var m = plugins[id]
        rows.push({
          id: id,
          manifest: m,
          enabled: root.pluginRegistry.isEnabled(id),
          firstParty: !!m.__isFirstParty
        })
      }
      return rows
    }

    function firstPartyList() {
      return pm.pluginList().filter(function(p) { return p.firstParty })
    }
    function thirdPartyList() {
      return pm.pluginList().filter(function(p) { return !p.firstParty })
    }
    function loadedCount() {
      var list = pm.pluginList()
      var n = 0
      for (var i = 0; i < list.length; i++) if (list[i].enabled) n++
      return n
    }

    spacing: 14
    Layout.fillWidth: true

    Row {
      Layout.fillWidth: true
      spacing: 12

      Text {
        text: {
          var total = pm.pluginList().length
          var loaded = pm.loadedCount()
          return total + " installed  ·  " + loaded + " loaded"
        }
        color: Qt.darker(root.foreground, 1.3)
        font.family: root.fontFamily
        font.pixelSize: 12
        anchors.verticalCenter: parent.verticalCenter
      }

      Item {
        height: 1
        width: Math.max(0, pm.width - rescanPill.width - rescanCount.implicitWidth - 24)
      }

      Text {
        id: rescanCount
        visible: false
        text: pm.pluginList().length + " installed"
      }

      ActionPill {
        id: rescanPill
        anchors.verticalCenter: parent.verticalCenter
        text: "[r] Rescan"
        onClicked: if (root.pluginRegistry) root.pluginRegistry.rescan()
      }
    }

    BracketedFrame {
      sectionIndex: 1
      sectionLabel: "FIRST-PARTY"
      sectionMeta: pm.firstPartyList().length + " plugins  ·  always enabled"

      Repeater {
        model: pm.firstPartyList()
        delegate: PluginInfoRow {
          required property var modelData
          required property int index
          width: parent.width
          rowIndex: index
          manifest: modelData.manifest
          pluginId: modelData.id
          pluginEnabled: modelData.enabled
          firstParty: modelData.firstParty
          onToggleEnabled: if (!firstParty && root.pluginRegistry)
            root.pluginRegistry.setEnabled(pluginId, !pluginEnabled)
        }
      }

      Item {
        visible: pm.firstPartyList().length === 0
        width: parent.width
        height: 24
        Text {
          anchors.centerIn: parent
          text: "no first-party plugins"
          color: Qt.darker(root.foreground, 1.6)
          font.family: root.fontFamily
          font.pixelSize: 12
          font.italic: true
        }
      }
    }

    BracketedFrame {
      sectionIndex: 2
      sectionLabel: "THIRD-PARTY"
      sectionMeta: pm.thirdPartyList().length + " plugins  ·  run at your own risk"

      Repeater {
        model: pm.thirdPartyList()
        delegate: PluginInfoRow {
          required property var modelData
          required property int index
          width: parent.width
          rowIndex: index
          manifest: modelData.manifest
          pluginId: modelData.id
          pluginEnabled: modelData.enabled
          firstParty: modelData.firstParty
          onToggleEnabled: if (!firstParty && root.pluginRegistry)
            root.pluginRegistry.setEnabled(pluginId, !pluginEnabled)
        }
      }

      Item {
        visible: pm.thirdPartyList().length === 0
        width: parent.width
        height: 24
        Text {
          anchors.centerIn: parent
          text: "no third-party plugins · drop folders into ~/.config/omarchy/plugins/"
          color: Qt.darker(root.foreground, 1.6)
          font.family: root.fontFamily
          font.pixelSize: 12
          font.italic: true
        }
      }
    }

    Text {
      Layout.fillWidth: true
      Layout.topMargin: 6
      text: "# tip  ·  plugin source lives at ~/.config/omarchy/plugins/. Drop a folder there and run :scan (or press r)."
      color: Qt.darker(root.foreground, 1.7)
      font.family: root.fontFamily
      font.pixelSize: 12
      wrapMode: Text.WordWrap
    }
  }

  // Numbered plugin row — two-line content. Line 1: name + version + author
  // + trailing "loaded"/"disabled" + [x]/[ ]. Line 2: description (dim).
  // First-party rows are non-interactive but still rendered (they're always
  // on).
  component PluginInfoRow: Item {
    id: pir
    property int rowIndex: 0
    property var manifest: ({})
    property string pluginId: ""
    property bool pluginEnabled: false
    property bool firstParty: false
    signal toggleEnabled()

    readonly property string displayName: (manifest && manifest.name) ? manifest.name : pluginId
    readonly property string versionStr: (manifest && manifest.version) ? "v" + manifest.version : ""
    readonly property string authorStr: (manifest && manifest.author)
      ? manifest.author
      : (firstParty ? "omarchy" : "third-party")
    readonly property string descStr: (manifest && manifest.description) ? manifest.description : ""

    implicitHeight: descStr ? 42 : 26
    activeFocusOnTab: !pir.firstParty
    opacity: pir.firstParty ? 0.85 : 1

    onActiveFocusChanged: {
      if (activeFocus) {
        root.selectedSection = ""
        root.selectedIndex = -1
      }
    }

    Keys.onReturnPressed: if (!pir.firstParty) pir.toggleEnabled()
    Keys.onEnterPressed:  if (!pir.firstParty) pir.toggleEnabled()
    Keys.onSpacePressed:  if (!pir.firstParty) pir.toggleEnabled()

    Rectangle {
      anchors.fill: parent
      color: pir.activeFocus
        ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
        : (pirArea.containsMouse && !pir.firstParty ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05) : "transparent")
      radius: root.cornerRadius
      Behavior on color { ColorAnimation { duration: 80 } }
    }

    Text {
      text: pir.activeFocus ? "▶" : ""
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: 11
      anchors.left: parent.left
      anchors.leftMargin: 6
      anchors.top: parent.top
      anchors.topMargin: 6
      width: 12
    }

    Text {
      text: root.padTwo(pir.rowIndex + 1)
      color: Qt.darker(root.foreground, 1.9)
      font.family: root.fontFamily
      font.pixelSize: 12
      anchors.left: parent.left
      anchors.leftMargin: 24
      anchors.top: parent.top
      anchors.topMargin: 6
    }

    Row {
      id: titleRow
      anchors.left: parent.left
      anchors.leftMargin: 56
      anchors.right: trailLabel.left
      anchors.rightMargin: 12
      anchors.top: parent.top
      anchors.topMargin: 6
      spacing: 8
      clip: true

      Text {
        text: pir.displayName
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 13
        font.bold: true
      }
      Text {
        visible: pir.versionStr !== ""
        text: pir.versionStr
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: 12
      }
      Text {
        text: "·"
        color: Qt.darker(root.foreground, 1.7)
        font.family: root.fontFamily
        font.pixelSize: 12
      }
      Text {
        text: pir.authorStr
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: 12
      }
    }

    Text {
      visible: pir.descStr !== ""
      text: pir.descStr
      color: Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: 12
      anchors.left: parent.left
      anchors.leftMargin: 56
      anchors.right: parent.right
      anchors.rightMargin: 12
      anchors.top: titleRow.bottom
      anchors.topMargin: 2
      elide: Text.ElideRight
    }

    Text {
      id: trailLabel
      text: pir.pluginEnabled ? "loaded" : "disabled"
      color: pir.pluginEnabled ? root.accent : Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: 12
      font.bold: pir.pluginEnabled
      anchors.right: trailSwitch.left
      anchors.rightMargin: 8
      anchors.top: parent.top
      anchors.topMargin: 6
    }

    Text {
      id: trailSwitch
      text: pir.pluginEnabled ? "[x]" : "[ ]"
      color: pir.pluginEnabled ? root.accent : Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: 13
      font.bold: pir.pluginEnabled
      anchors.right: parent.right
      anchors.rightMargin: 12
      anchors.top: parent.top
      anchors.topMargin: 6
    }

    MouseArea {
      id: pirArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: pir.firstParty ? Qt.ForbiddenCursor : Qt.PointingHandCursor
      onClicked: if (!pir.firstParty) { pir.forceActiveFocus(); pir.toggleEnabled() }
    }
  }
}
