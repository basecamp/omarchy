import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

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
  property color foreground: "#cacccc"
  property color background: "#101315"
  property color accent: "#cacccc"
  property color urgent: "#a55555"
  property string fontFamily: "JetBrainsMono Nerd Font"

  // Source-of-truth for the shell-wide corner radius. Mirrors what the menu
  // reads from quickshell-menu.json so `omarchy style corners <sharp|round>`
  // flips both surfaces together.
  property int cornerRadius: 0

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
      fontFamily: "JetBrainsMono Nerd Font",
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
  property var draft: ({ version: 1, bar: { position: "top", centerAnchor: "calendar", fontFamily: "JetBrainsMono Nerd Font", layout: { left: [], center: [], right: [] } }, plugins: [] })
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
        fontFamily: String(bar.fontFamily || "JetBrainsMono Nerd Font"),
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

  function loadTheme(raw) {
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (!match) continue
      if (match[1] === "foreground") foreground = match[2]
      else if (match[1] === "background") background = match[2]
      else if (match[1] === "color4" || match[1] === "accent") accent = match[2]
      else if (match[1] === "red") urgent = match[2]
    }
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

  // `omarchy-theme-set` does `rm -rf current/theme && mv next-theme current/theme`.
  // The atomic swap invalidates the inotify watch on colors.toml (the file's
  // inode is gone), so onFileChanged never fires for theme switches. Use
  // theme.name — a stable file overwritten in place — as the tripwire and
  // force-reload colors.toml from its new path each time it changes.
  FileView {
    id: themeColorsFile
    path: root.home + "/.config/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadTheme(text())
    onFileChanged: reload()
  }
  FileView {
    path: root.home + "/.config/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: themeColorsFile.reload()
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
          switch (event.key) {
          case Qt.Key_Escape:
          case Qt.Key_H:
          case Qt.Key_Left:
          case Qt.Key_Backtab:
            root.exitBodyZone(); event.accepted = true; return
          case Qt.Key_J:
          case Qt.Key_Down:
          case Qt.Key_Tab:
            root.focusBodyDelta(+1); event.accepted = true; return
          case Qt.Key_K:
          case Qt.Key_Up:
            root.focusBodyDelta(-1); event.accepted = true; return
          }
          if (ctrl && event.key === Qt.Key_H) { root.exitBodyZone(); event.accepted = true; return }
        }
      }

    Rectangle {
      anchors.fill: parent
      color: root.background
      // No explicit border — the Hyprland window decoration already draws one.

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header
        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: 48

          Text {
            text: "Omarchy Settings"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 16
            font.bold: true
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            text: "~/.config/omarchy/shell.json"
            color: Qt.darker(root.foreground, 1.8)
            font.family: root.fontFamily
            font.pixelSize: 10
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
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
              anchors.margins: 8
              spacing: 2

              SidebarRow { categoryId: "defaults"; label: "Defaults"; glyph: "󰀻" }
              SidebarRow { categoryId: "style";    label: "Style";    glyph: "󰏘" }
              SidebarRow { categoryId: "bar";      label: "Bar";      glyph: "󰛼" }
              SidebarRow { categoryId: "system";   label: "System";   glyph: "󰒓" }
              SidebarRow { categoryId: "plugins";  label: "Plugins";  glyph: "󰐱" }

              Item { Layout.fillHeight: true }
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
      }
    }
    }
  }

  // ===================== sidebar row =======================================
  component SidebarRow: Rectangle {
    id: sb
    property string categoryId: ""
    property string label: ""
    property string glyph: ""
    readonly property bool active: root.activeCategory === categoryId
    readonly property bool sidebarFocused: root.focusZone === "sidebar"

    Layout.fillWidth: true
    Layout.preferredHeight: 30
    radius: root.cornerRadius
    color: sb.active
      ? (sb.sidebarFocused
          ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.20)
          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14))
      : (sbArea.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07) : "transparent")
    border.color: sb.active
      ? (sb.sidebarFocused ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25))
      : "transparent"
    border.width: sb.active && sb.sidebarFocused ? 2 : 1

    Behavior on color { ColorAnimation { duration: 100 } }

    Row {
      anchors.left: parent.left
      anchors.leftMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      spacing: 10

      Text {
        text: sb.glyph
        color: sb.active ? root.accent : Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: 13
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        text: sb.label
        color: sb.active ? root.foreground : Qt.darker(root.foreground, 1.2)
        font.family: root.fontFamily
        font.pixelSize: 12
        font.bold: sb.active
        anchors.verticalCenter: parent.verticalCenter
      }
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
    spacing: 14

    Text {
      text: "Bar"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: 18
      font.bold: true
    }

    Text {
      text: "Drag widgets between the bar's three sections, drop in plugin widgets, and tweak per-widget options. Auto-saves to shell.json."
      color: Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: 11
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    Row {
      Layout.fillWidth: true
      spacing: 14

      Cmp.NDropdown {
        label: "Position"
        value: root.draft.bar.position
        options: ["top", "right", "bottom", "left"]
        foreground: root.foreground
        background: root.background
        accent: root.accent
        fontFamily: root.fontFamily
        cornerRadius: root.cornerRadius
        onChanged: function(v) {
          var next = root.cloneJson(root.draft)
          next.bar.position = v
          root.draft = next
          root.markDirty()
        }
      }

      Cmp.NDropdown {
        label: "Center anchor"
        value: root.draft.bar.centerAnchor || "(none)"
        options: {
          var list = ["(none)"]
          var entries = root.draft.bar.layout.center || []
          for (var i = 0; i < entries.length; i++) list.push(entries[i].id)
          return list
        }
        foreground: root.foreground
        background: root.background
        accent: root.accent
        fontFamily: root.fontFamily
        cornerRadius: root.cornerRadius
        onChanged: function(v) {
          var next = root.cloneJson(root.draft)
          next.bar.centerAnchor = v === "(none)" ? "" : v
          root.draft = next
          root.markDirty()
        }
      }
    }

    SectionEditor { sectionKey: "left";    sectionLabel: "Bar · Left" }
    SectionEditor { sectionKey: "center";  sectionLabel: "Bar · Center" }
    SectionEditor { sectionKey: "right";   sectionLabel: "Bar · Right" }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
    }

    Row {
      Layout.alignment: Qt.AlignRight
      ActionPill {
        text: "Reset to defaults"
        foreground: root.urgent
        onClicked: root.resetToDefaults()
      }
    }
  }

  // ===================== defaults category =================================
  component DefaultsCategory: ColumnLayout {
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
      stdout: SplitParser { onRead: function(line) { terminalCurrent = String(line).trim() } }
    }
    Process {
      id: readBrowserProc
      command: ["omarchy-default-browser"]
      stdout: SplitParser { onRead: function(line) { browserCurrent = String(line).trim() } }
    }
    Process {
      id: readEditorProc
      command: ["omarchy-default-editor"]
      stdout: SplitParser { onRead: function(line) { editorCurrent = String(line).trim() } }
    }
    // Refresh after the write has actually finished — kicking off a read
    // synchronously after .running = true races the bash apply and ends up
    // displaying the *previous* default.
    Process {
      id: applyDefaultsProc
      onExited: refresh()
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

    Text {
      text: "Defaults"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: 18
      font.bold: true
    }

    Text {
      text: "Pick the terminal, browser, and editor Omarchy hands off to when launching apps."
      color: Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: 11
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    DefaultsGroup {
      title: "Terminal"
      description: "Used by Super+Return and xdg-terminal-exec."
      options: [
        { id: "alacritty", label: "Alacritty",   cmd: "alacritty" },
        { id: "foot",      label: "Foot",        cmd: "foot" },
        { id: "ghostty",   label: "Ghostty",     cmd: "ghostty" },
        { id: "kitty",     label: "Kitty",       cmd: "kitty" }
      ]
      currentId: terminalCurrent
      onPicked: function(id) { applyDefault("terminal", id) }
    }

    DefaultsGroup {
      title: "Browser"
      description: "Used for x-scheme-handler/http and HTML files."
      options: [
        { id: "chromium",     label: "Chromium",     cmd: "chromium" },
        { id: "chrome",       label: "Chrome",       cmd: "google-chrome-stable" },
        { id: "brave",        label: "Brave",        cmd: "brave" },
        { id: "brave-origin", label: "Brave Origin", cmd: "brave-origin-beta" },
        { id: "edge",         label: "Edge",         cmd: "microsoft-edge-stable" },
        { id: "firefox",      label: "Firefox",      cmd: "firefox" },
        { id: "zen",          label: "Zen",          cmd: "zen-browser" }
      ]
      currentId: browserCurrent
      onPicked: function(id) { applyDefault("browser", id) }
    }

    DefaultsGroup {
      title: "Editor"
      description: "Sets $EDITOR. Takes effect after the next login."
      options: [
        { id: "nvim",         label: "Neovim",       cmd: "nvim" },
        { id: "code",         label: "VSCode",       cmd: "code" },
        { id: "cursor",       label: "Cursor",       cmd: "cursor" },
        { id: "zeditor",      label: "Zed",          cmd: "zeditor" },
        { id: "sublime_text", label: "Sublime Text", cmd: "sublime_text" },
        { id: "helix",        label: "Helix",        cmd: "helix" },
        { id: "vim",          label: "Vim",          cmd: "vim" },
        { id: "emacs",        label: "Emacs",        cmd: "emacs" }
      ]
      currentId: editorCurrent
      onPicked: function(id) { applyDefault("editor", id) }
    }
  }

  component DefaultsGroup: Column {
    id: dg
    property string title: ""
    property string description: ""
    property var options: []
    property string currentId: ""
    signal picked(string id)

    Layout.fillWidth: true
    Layout.topMargin: 8
    spacing: 6

    Row {
      width: dg.width
      spacing: 8
      Text {
        text: dg.title
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 13
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        text: "·  " + dg.description
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: 10
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Column {
      width: dg.width
      spacing: 4

      Repeater {
        model: dg.options
        delegate: DefaultsRow {
          required property var modelData
          width: dg.width
          optionId: modelData.id
          optionLabel: modelData.label
          checkCmd: modelData.cmd
          selected: dg.currentId === modelData.id
          onClicked: dg.picked(optionId)
        }
      }
    }
  }

  component DefaultsRow: Rectangle {
    id: dr
    property string optionId: ""
    property string optionLabel: ""
    property string checkCmd: ""
    property bool selected: false
    property bool available: false
    signal clicked()

    activeFocusOnTab: dr.available
    Keys.onReturnPressed: if (dr.available && !dr.selected) dr.clicked()
    Keys.onEnterPressed: if (dr.available && !dr.selected) dr.clicked()
    Keys.onSpacePressed: if (dr.available && !dr.selected) dr.clicked()

    implicitHeight: 38
    radius: root.cornerRadius
    color: dr.activeFocus
      ? root.focusFillColor
      : (drArea.containsMouse
          ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03))
    border.color: dr.activeFocus
      ? root.focusBorderColor
      : (dr.selected ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12))
    border.width: dr.activeFocus ? root.focusBorderWidth : 1
    opacity: dr.available ? 1 : 0.45

    Behavior on color { ColorAnimation { duration: 100 } }

    // Probe availability via `command -v`. Cached for the lifetime of the row.
    Process {
      id: probeProc
      command: ["bash", "-lc", "command -v " + dr.checkCmd + " >/dev/null && echo yes || echo no"]
      stdout: SplitParser { onRead: function(line) { dr.available = String(line).trim() === "yes" } }
      Component.onCompleted: running = true
    }

    Row {
      anchors.left: parent.left
      anchors.leftMargin: 12
      anchors.right: trailRow.left
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      spacing: 10

      Text {
        text: dr.selected ? "●" : "○"
        color: dr.selected ? root.accent : Qt.darker(root.foreground, 1.3)
        font.family: root.fontFamily
        font.pixelSize: 12
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        text: dr.optionLabel
        color: dr.selected ? root.foreground : Qt.darker(root.foreground, 1.05)
        font.family: root.fontFamily
        font.pixelSize: 12
        font.bold: dr.selected
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        text: dr.checkCmd
        color: Qt.darker(root.foreground, 1.7)
        font.family: root.fontFamily
        font.pixelSize: 10
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Row {
      id: trailRow
      anchors.right: parent.right
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      spacing: 6

      Text {
        visible: !dr.available
        text: "not installed"
        color: Qt.darker(root.foreground, 1.7)
        font.family: root.fontFamily
        font.pixelSize: 10
      }
      Text {
        visible: dr.selected
        text: "default"
        color: root.accent
        font.family: root.fontFamily
        font.pixelSize: 10
      }
    }

    MouseArea {
      id: drArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: dr.available ? Qt.PointingHandCursor : Qt.ForbiddenCursor
      onClicked: if (dr.available && !dr.selected) dr.clicked()
    }
  }

  // ===================== style category ====================================
  component StyleCategory: ColumnLayout {
    spacing: 14

    property string currentCorners: root.cornerRadius > 0 ? "round" : "sharp"
    property bool barOn: true
    property bool gapsOn: true
    property bool oneWinSquare: false
    property string monitorName: ""
    property string monitorScale: ""
    property string themeName: ""
    property string themeSlug: ""
    property string themePreview: ""
    property string fontName: ""
    property string backgroundPath: ""
    property string backgroundName: ""
    property var fontsList: []
    property int refreshTick: 0

    function refresh() {
      refreshTick++
      readBarProc.running = true
      readGapsProc.running = true
      readOneWinSqProc.running = true
      readMonitorProc.running = true
      readThemeProc.running = true
      readFontProc.running = true
      readFontsListProc.running = true
      readBackgroundProc.running = true
    }

    Process { id: applyStyleProc; onExited: refresh() }

    // Emits 3 lines: display name, slug, preview path — for the *current*
    // theme only. Cheap enough that we don't bother caching the full list.
    Process {
      id: readThemeProc
      command: ["bash", "-lc",
        "name=$(omarchy-theme-current 2>/dev/null); " +
        "slug=$(cat $HOME/.config/omarchy/current/theme.name 2>/dev/null); " +
        "preview=''; " +
        "for base in \"$HOME/.config/omarchy/themes\" \"$OMARCHY_PATH/themes\"; do " +
        "  [[ -d $base/$slug ]] || continue; " +
        "  for ext in png jpg jpeg webp; do " +
        "    if [[ -f $base/$slug/preview.$ext ]]; then preview=\"$base/$slug/preview.$ext\"; break 2; fi; " +
        "  done; " +
        "  if [[ -z $preview && -d $base/$slug/backgrounds ]]; then " +
        "    preview=$(find -L \"$base/$slug/backgrounds\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.png' -o -iname '*.webp' \\) 2>/dev/null | sort | head -n1); " +
        "    [[ -n $preview ]] && break; " +
        "  fi; " +
        "done; " +
        "printf '%s\\n%s\\n%s\\n' \"$name\" \"$slug\" \"$preview\""
      ]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          var lines = String(text || "").split("\n")
          themeName = (lines[0] || "").trim()
          themeSlug = (lines[1] || "").trim()
          themePreview = (lines[2] || "").trim()
        }
      }
    }
    Process {
      id: readFontProc
      command: ["omarchy-font-current"]
      stdout: SplitParser { onRead: function(line) { fontName = String(line).trim() } }
    }
    Process {
      id: readFontsListProc
      command: ["omarchy-font-list"]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: fontsList = String(text || "").trim().split("\n").filter(function(x) { return x.length > 0 })
      }
    }
    Process {
      id: readBackgroundProc
      command: ["bash", "-lc", "readlink -f $HOME/.config/omarchy/current/background 2>/dev/null"]
      stdout: SplitParser { onRead: function(line) {
        backgroundPath = String(line).trim()
        var i = backgroundPath.lastIndexOf("/")
        backgroundName = i >= 0 ? backgroundPath.substring(i + 1) : backgroundPath
      } }
    }

    // Pick up theme/background changes that happen via the menu / CLI without
    // going through the Style category's own buttons.
    FileView {
      path: root.home + "/.config/omarchy/current/theme.name"
      watchChanges: true
      printErrors: false
      onFileChanged: refresh()
      onLoaded: refresh()
    }
    FileView {
      path: root.home + "/.config/alacritty/alacritty.toml"
      watchChanges: true
      printErrors: false
      onFileChanged: refresh()
    }

    // Re-read when any toggle flag changes on disk — covers CLI/menu paths
    // that mutate `~/.local/state/omarchy/toggles/*` without going through us.
    FileView {
      path: root.home + "/.local/state/omarchy/toggles"
      watchChanges: true
      printErrors: false
      onFileChanged: refresh()
    }
    FileView {
      path: root.home + "/.local/state/omarchy/toggles/hypr"
      watchChanges: true
      printErrors: false
      onFileChanged: refresh()
    }

    Process {
      id: readBarProc
      command: ["bash", "-lc", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo no || echo yes"]
      stdout: SplitParser { onRead: function(line) { barOn = String(line).trim() === "yes" } }
    }
    Process {
      id: readGapsProc
      command: ["bash", "-lc", "[[ -f $HOME/.local/state/omarchy/toggles/hypr/window-no-gaps.lua ]] && echo no || echo yes"]
      stdout: SplitParser { onRead: function(line) { gapsOn = String(line).trim() === "yes" } }
    }
    Process {
      id: readOneWinSqProc
      command: ["bash", "-lc", "[[ -f $HOME/.local/state/omarchy/toggles/hypr/single-window-aspect-ratio.lua ]] && echo yes || echo no"]
      stdout: SplitParser { onRead: function(line) { oneWinSquare = String(line).trim() === "yes" } }
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
          monitorName = parts[0]
          monitorScale = snapScale(parts[1])
        }
      } }
    }

    function runStyle(cmd) {
      applyStyleProc.command = ["bash", "-lc", cmd]
      applyStyleProc.running = true
    }

    Component.onCompleted: refresh()
    onVisibleChanged: if (visible) refresh()

    Text {
      text: "Style"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: 18
      font.bold: true
    }

    Text {
      text: "Look-and-feel of the shell, lock screen, and windows."
      color: Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: 11
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    // Theme + Background side by side. Both defer to the existing Walker
    // pickers; the rows here just surface the current selection.
    RowLayout {
      Layout.fillWidth: true
      spacing: 14

      ThumbLaunchRow {
        Layout.fillWidth: true
        label: "Theme"
        currentValue: themeName || "—"
        thumbnailPath: themePreview
        buttonText: "Choose theme…"
        onLaunch: runStyle("bash -lc 'theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set \"$theme\"'")
      }

      ThumbLaunchRow {
        Layout.fillWidth: true
        label: "Background"
        currentValue: backgroundName || "—"
        thumbnailPath: backgroundPath
        buttonText: "Choose background…"
        onLaunch: runStyle("bash -lc 'background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\"'")
      }
    }

    StyleToggleRow {
      label: "Window gaps"
      description: "Tile windows with the default gap between them."
      isOn: gapsOn
      onToggle: runStyle("omarchy-hyprland-window-gaps-toggle")
    }

    StyleToggleRow {
      label: "1-window square ratio"
      description: "Constrain a solo tiled window to a square aspect."
      isOn: oneWinSquare
      onToggle: runStyle("omarchy-hyprland-window-single-square-aspect-toggle")
    }

    StyleToggleRow {
      label: "Bar"
      description: "Show the omarchy bar. The shell keeps running either way, so menus and this panel stay reachable."
      isOn: barOn
      onToggle: runStyle("omarchy-toggle-bar")
    }

    // Corner style — a real picker since this changes the whole shell's look.
    ColumnLayout {
      Layout.fillWidth: true
      Layout.topMargin: 8
      spacing: 6

      Row {
        spacing: 8
        Text {
          text: "Corners"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: 13
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          text: "·  Sharp matches the retro TUI look; round softens windows, menus, and notifications."
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: 10
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Row {
        spacing: 8

        StyleOptionTile {
          tileLabel: "Sharp"
          tileHint: "0px radius"
          selected: currentCorners === "sharp"
          onClicked: runStyle("omarchy-style-corners sharp")
        }
        StyleOptionTile {
          tileLabel: "Round"
          tileHint: "6px radius"
          selected: currentCorners === "round"
          onClicked: runStyle("omarchy-style-corners round")
        }
      }
    }

    // Monitor scaling — explicit picker. The Super+Plus/Minus shortcuts still
    // call `omarchy-hyprland-monitor-scaling-cycle` for keyboard cycling.
    ColumnLayout {
      Layout.fillWidth: true
      Layout.topMargin: 8
      spacing: 6

      Row {
        spacing: 8
        Text {
          text: "Monitor scaling"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: 13
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          text: "·  Pick a scale for " + (monitorName || "the focused monitor") + ". Keyboard shortcut still cycles."
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: 10
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Row {
        spacing: 8

        Repeater {
          model: ["1", "1.25", "1.6", "2", "3", "4"]
          delegate: StyleChip {
            required property var modelData
            label: modelData + "×"
            selected: monitorScale === modelData
            onClicked: runStyle("omarchy-hyprland-monitor-scaling-set " + modelData)
          }
        }
      }
    }

    // Font picker — each row rendered in its own typeface. Sits at the
    // bottom because it's long; everything else above is one-line tall.
    ColumnLayout {
      Layout.fillWidth: true
      Layout.topMargin: 8
      spacing: 6

      Row {
        spacing: 8
        Text {
          text: "Font"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: 13
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          text: "·  " + (fontName || "—")
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: 10
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Repeater {
          model: fontsList
          delegate: FontRow {
            required property var modelData
            Layout.fillWidth: true
            fontFamilyName: modelData
            selected: modelData === fontName
            onPicked: runStyle("omarchy-font-set \"" + modelData + "\"")
          }
        }
      }
    }
  }

  // ===================== system category ===================================
  component SystemCategory: ColumnLayout {
    spacing: 14

    property string powerProfile: ""
    property var powerProfiles: []
    property bool nightlightOn: false
    property bool dndOn: false
    property bool idleOn: false
    property bool screensaverOn: false
    property bool suspendAvailable: true
    property int refreshTick: 0

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

    Process { id: applySystemProc; onExited: refresh() }

    Process {
      id: readPowerProc
      command: ["bash", "-lc", "powerprofilesctl get 2>/dev/null"]
      stdout: SplitParser { onRead: function(line) { powerProfile = String(line).trim() } }
    }
    Process {
      id: readPowerListProc
      command: ["bash", "-lc", "omarchy-powerprofiles-list 2>/dev/null"]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: powerProfiles = String(text || "").trim().split("\n").filter(function(x) { return x.length > 0 })
      }
    }
    Process {
      id: readNightlightProc
      command: ["bash", "-lc", "hyprctl hyprsunset temperature 2>/dev/null | grep -oE '[0-9]+' | head -n1 || echo 6000"]
      stdout: SplitParser { onRead: function(line) {
        var n = parseInt(String(line).trim(), 10)
        nightlightOn = isFinite(n) && n < 5500
      } }
    }
    Process {
      id: readDndProc
      command: ["bash", "-lc", "omarchy-shell-ipc notifications isDnd 2>/dev/null || echo off"]
      stdout: SplitParser { onRead: function(line) { dndOn = String(line).trim() === "on" } }
    }
    Process {
      id: readIdleProc
      command: ["bash", "-lc", "pgrep -x hypridle >/dev/null && echo yes || echo no"]
      stdout: SplitParser { onRead: function(line) { idleOn = String(line).trim() === "yes" } }
    }
    Process {
      id: readScreensaverProc
      command: ["bash", "-lc", "[[ -f $HOME/.local/state/omarchy/toggles/screensaver-off ]] && echo no || echo yes"]
      stdout: SplitParser { onRead: function(line) { screensaverOn = String(line).trim() === "yes" } }
    }
    Process {
      id: readSuspendProc
      command: ["bash", "-lc", "[[ -f $HOME/.local/state/omarchy/toggles/suspend-off ]] && echo no || echo yes"]
      stdout: SplitParser { onRead: function(line) { suspendAvailable = String(line).trim() === "yes" } }
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
      onFileChanged: refresh()
    }

    Component.onCompleted: refresh()
    onVisibleChanged: if (visible) refresh()

    Text {
      text: "System"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: 18
      font.bold: true
    }

    Text {
      text: "System-level behavior — power, notifications, idle, screensaver, suspend."
      color: Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: 11
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.topMargin: 8
      spacing: 6

      Row {
        spacing: 8
        Text {
          text: "Power profile"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: 13
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          text: "·  Pick how aggressively the CPU clocks down. Reads via power-profiles-daemon."
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: 10
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Row {
        spacing: 8

        Repeater {
          model: powerProfiles
          delegate: StyleChip {
            required property var modelData
            label: modelData.charAt(0).toUpperCase() + modelData.slice(1).replace("-", " ")
            selected: powerProfile === modelData
            onClicked: runSystem("powerprofilesctl set " + modelData)
          }
        }
      }
    }

    StyleToggleRow {
      label: "Nightlight"
      description: "Lower screen colour temperature in the evening."
      isOn: nightlightOn
      onToggle: runSystem("omarchy-toggle-nightlight")
    }

    StyleToggleRow {
      label: "Notifications"
      description: dndOn ? "Do-not-disturb is on — notifications are silenced." : "Notifications post normally."
      isOn: !dndOn
      onToggle: runSystem("omarchy-toggle-notification-silencing")
    }

    StyleToggleRow {
      label: "Idle locking"
      description: "Lock the screen when idle (hypridle)."
      isOn: idleOn
      onToggle: runSystem("omarchy-toggle-idle")
    }

    StyleToggleRow {
      label: "Screensaver"
      description: "Allow the screensaver to engage during idle."
      isOn: screensaverOn
      onToggle: runSystem("omarchy-toggle-screensaver")
    }

    StyleToggleRow {
      label: "Suspend in system menu"
      description: "Show 'Suspend' in the system power menu."
      isOn: suspendAvailable
      onToggle: runSystem("omarchy-toggle-suspend")
    }
  }

  component StyleOptionTile: Rectangle {
    id: tile
    property string tileLabel: ""
    property string tileHint: ""
    property bool selected: false
    signal clicked()

    activeFocusOnTab: true
    Keys.onReturnPressed: tile.clicked()
    Keys.onEnterPressed: tile.clicked()
    Keys.onSpacePressed: tile.clicked()

    implicitWidth: 140
    implicitHeight: 52
    radius: root.cornerRadius
    color: tile.activeFocus
      ? root.focusFillColor
      : (tileArea.containsMouse
          ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03))
    border.color: tile.activeFocus
      ? root.focusBorderColor
      : (tile.selected ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18))
    border.width: tile.activeFocus ? root.focusBorderWidth : (tile.selected ? 2 : 1)

    Behavior on color { ColorAnimation { duration: 100 } }

    Text {
      id: tileTitle
      text: tile.tileLabel
      color: tile.selected ? root.foreground : Qt.darker(root.foreground, 1.1)
      font.family: root.fontFamily
      font.pixelSize: 13
      font.bold: tile.selected
      horizontalAlignment: Text.AlignHCenter
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: 10
    }
    Text {
      text: tile.tileHint
      color: Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: 10
      horizontalAlignment: Text.AlignHCenter
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: tileTitle.bottom
      anchors.topMargin: 2
    }

    MouseArea {
      id: tileArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tile.clicked()
    }
  }

  // Compact, single-line variant of StyleOptionTile — used for the monitor
  // scaling chip row where 6 options need to fit on one line.
  component StyleChip: Rectangle {
    id: chip
    property string label: ""
    property bool selected: false
    signal clicked()

    activeFocusOnTab: true
    Keys.onReturnPressed: chip.clicked()
    Keys.onEnterPressed: chip.clicked()
    Keys.onSpacePressed: chip.clicked()

    implicitWidth: chipText.implicitWidth + 22
    implicitHeight: 30
    radius: root.cornerRadius
    color: chip.activeFocus
      ? root.focusFillColor
      : (chipArea.containsMouse
          ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03))
    border.color: chip.activeFocus
      ? root.focusBorderColor
      : (chip.selected ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18))
    border.width: chip.activeFocus ? root.focusBorderWidth : (chip.selected ? 2 : 1)

    Behavior on color { ColorAnimation { duration: 100 } }

    Text {
      id: chipText
      anchors.centerIn: parent
      text: chip.label
      color: chip.selected ? root.foreground : Qt.darker(root.foreground, 1.1)
      font.family: root.fontFamily
      font.pixelSize: 12
      font.bold: chip.selected
    }

    MouseArea {
      id: chipArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.clicked()
    }
  }

  // Row showing a thumbnail of the current value on the left, label + current
  // value in the middle, and a launch button on the right. Used for theme and
  // background where the actual picker is an external Walker UI.
  component ThumbLaunchRow: Rectangle {
    id: tlr
    property string label: ""
    property string currentValue: "—"
    property string thumbnailPath: ""
    property string buttonText: "Choose…"
    signal launch()

    Layout.fillWidth: true
    implicitHeight: 64
    radius: root.cornerRadius
    color: tlrArea.containsMouse
      ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
    border.width: 1

    Behavior on color { ColorAnimation { duration: 100 } }

    Rectangle {
      id: tlrThumb
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.margins: 8
      width: height * 1.6
      radius: root.cornerRadius
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)
      border.width: 1
      clip: true

      Image {
        anchors.fill: parent
        anchors.margins: 1
        source: tlr.thumbnailPath ? ("file://" + tlr.thumbnailPath) : ""
        visible: tlr.thumbnailPath !== ""
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 240
        asynchronous: true
        cache: true
      }
    }

    Column {
      anchors.left: tlrThumb.right
      anchors.leftMargin: 14
      anchors.right: tlrButton.left
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      spacing: 2

      Text {
        text: tlr.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 12
        font.bold: true
      }
      Text {
        text: tlr.currentValue
        color: Qt.darker(root.foreground, 1.3)
        font.family: root.fontFamily
        font.pixelSize: 11
        elide: Text.ElideRight
        width: parent.width
      }
    }

    ActionPill {
      id: tlrButton
      anchors.right: parent.right
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      text: tlr.buttonText
      onClicked: tlr.launch()
    }

    MouseArea {
      id: tlrArea
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }
  }

  // Row showing a font name rendered in its own typeface, plus a short sample
  // string in the same font. Selected = accent border + bold.
  component FontRow: Rectangle {
    id: fr
    property string fontFamilyName: ""
    property bool selected: false
    signal picked()

    activeFocusOnTab: true
    Keys.onReturnPressed: if (!fr.selected) fr.picked()
    Keys.onEnterPressed: if (!fr.selected) fr.picked()
    Keys.onSpacePressed: if (!fr.selected) fr.picked()

    implicitHeight: 44
    radius: root.cornerRadius
    color: fr.activeFocus
      ? root.focusFillColor
      : (frArea.containsMouse
          ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03))
    border.color: fr.activeFocus
      ? root.focusBorderColor
      : (fr.selected ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12))
    border.width: fr.activeFocus ? root.focusBorderWidth : (fr.selected ? 2 : 1)

    Behavior on color { ColorAnimation { duration: 100 } }

    Row {
      anchors.fill: parent
      anchors.leftMargin: 14
      anchors.rightMargin: 14
      spacing: 14

      Text {
        text: fr.fontFamilyName
        color: fr.selected ? root.accent : root.foreground
        font.family: fr.fontFamilyName
        font.pixelSize: 13
        font.bold: fr.selected
        anchors.verticalCenter: parent.verticalCenter
        width: 220
        elide: Text.ElideRight
      }
      Text {
        text: "The quick brown fox jumps over the lazy dog 0123"
        color: Qt.darker(root.foreground, 1.3)
        font.family: fr.fontFamilyName
        font.pixelSize: 12
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        width: parent.width - 234
      }
    }

    MouseArea {
      id: frArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: if (!fr.selected) fr.picked()
    }
  }


  component StyleToggleRow: Rectangle {
    id: tr
    property string label: ""
    property string description: ""
    property bool isOn: false
    signal toggle()

    activeFocusOnTab: true
    Keys.onReturnPressed: tr.toggle()
    Keys.onEnterPressed: tr.toggle()
    Keys.onSpacePressed: tr.toggle()

    Layout.fillWidth: true
    implicitHeight: 46
    radius: root.cornerRadius
    color: tr.activeFocus
      ? root.focusFillColor
      : (trArea.containsMouse
          ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03))
    border.color: tr.activeFocus ? root.focusBorderColor : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
    border.width: tr.activeFocus ? root.focusBorderWidth : 1

    Behavior on color { ColorAnimation { duration: 100 } }

    Column {
      anchors.left: parent.left
      anchors.leftMargin: 14
      anchors.right: trSwitch.left
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      spacing: 2

      Text {
        text: tr.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 12
        font.bold: true
      }
      Text {
        text: tr.description
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: 10
        elide: Text.ElideRight
        width: parent.width
      }
    }

    Rectangle {
      id: trSwitch
      anchors.right: parent.right
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      width: 48
      height: 22
      radius: root.cornerRadius
      color: tr.isOn
        ? root.accent
        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
      border.color: tr.isOn ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.4)
      border.width: 1

      Rectangle {
        width: 16
        height: 16
        radius: root.cornerRadius
        color: tr.isOn ? root.background : root.foreground
        anchors.verticalCenter: parent.verticalCenter
        x: tr.isOn ? parent.width - width - 3 : 3

        Behavior on x { NumberAnimation { duration: 120 } }
      }
    }

    MouseArea {
      id: trArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tr.toggle()
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
      font.pixelSize: 11
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
      font.pixelSize: 13
    }

    MouseArea {
      id: iconArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: iconButton.clicked()
    }
  }

  // ===================== bar layout pieces =================================
  component SectionEditor: Column {
    id: section

    property string sectionKey: ""
    property string sectionLabel: ""
    property var entries: root.sectionArray(section.sectionKey)
    Layout.fillWidth: true
    Layout.topMargin: 8
    spacing: 8

    Connections {
      target: root
      function onDraftRevisionChanged() { section.entries = root.sectionArray(section.sectionKey) }
    }

    Row {
      width: section.width
      spacing: 8

      Text {
        text: section.sectionLabel
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 13
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: "·  " + section.entries.length + (section.entries.length === 1 ? " widget" : " widgets")
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: 11
        anchors.verticalCenter: parent.verticalCenter
      }

      Item {
        width: Math.max(0, section.width - 200 - 100)
        height: 1
      }

      ActionPill {
        id: addPill
        text: "+ Add widget"
        onClicked: addPopup.open()
      }
    }

    // Styled add-widget popup. Anchored under the "+ Add widget" pill,
    // pulls fresh data from the host's availableToAdd() each open.
    Popup {
      id: addPopup
      parent: addPill
      x: addPill.width - width
      y: addPill.height + 4
      width: 280
      implicitHeight: Math.min(addList.contentHeight + 2, 340)
      padding: 1
      modal: false
      focus: true

      background: Rectangle {
        color: root.background
        border.color: root.foreground
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
          height: 36
          color: addArea.containsMouse
            ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
            : "transparent"

          Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
              text: modelData.name
                + (modelData.isNoctalia ? "  (Noctalia)" : "")
                + (modelData.elsewhere ? "  (elsewhere)" : "")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 12
              elide: Text.ElideRight
              width: parent.width
            }
            Text {
              visible: text !== ""
              text: modelData.description || ""
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
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

    Column {
      Layout.fillWidth: true
      width: section.width
      spacing: 4

      Repeater {
        model: section.entries
        delegate: WidgetCard {
          required property var modelData
          required property int index
          width: section.width
          sectionKey: section.sectionKey
          entryIndex: index
          entry: modelData
        }
      }

      Rectangle {
        visible: section.entries.length === 0
        width: parent.width
        height: 32
        radius: root.cornerRadius
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
        border.width: 1

        Text {
          anchors.centerIn: parent
          text: "Empty — add a widget"
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: 11
        }
      }
    }
  }

  component WidgetCard: Rectangle {
    id: card
    property string sectionKey: ""
    property int entryIndex: -1
    property var entry: ({})
    readonly property string entryId: entry && entry.id ? String(entry.id) : ""
    readonly property string displayName: root.widgetName(entryId)
    readonly property string description: root.widgetDescription(entryId)
    readonly property bool hasSettings: root.widgetHasSettings(entryId)

    implicitHeight: 50
    radius: root.cornerRadius
    color: cardArea.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
    border.width: 1

    Behavior on color { ColorAnimation { duration: 100 } }

    Row {
      id: actionRow
      anchors.right: parent.right
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      spacing: 4

      IconButton {
        glyph: "↑"
        tooltip: "Move up"
        onClicked: root.moveEntry(card.sectionKey, card.entryIndex, card.entryIndex - 1)
      }
      IconButton {
        glyph: "↓"
        tooltip: "Move down"
        onClicked: root.moveEntry(card.sectionKey, card.entryIndex, card.entryIndex + 1)
      }
      IconButton {
        glyph: "⚙"
        tooltip: "Settings"
        visible: card.hasSettings
        onClicked: settingsLoader.open(card.entry)
      }
      IconButton {
        glyph: "✕"
        tooltip: "Remove"
        foreground: root.urgent
        onClicked: root.removeEntry(card.sectionKey, card.entryIndex)
      }
    }

    Column {
      anchors.left: parent.left
      anchors.right: actionRow.left
      anchors.leftMargin: 12
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      spacing: 2

      Text {
        text: card.displayName
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 12
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }
      Text {
        visible: text !== ""
        text: card.description
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: 10
        elide: Text.ElideRight
        width: parent.width
      }
    }

    MouseArea {
      id: cardArea
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    SettingsDialog {
      id: settingsLoader
      anchorWindow: window
      sectionKey: card.sectionKey
      entryIndex: card.entryIndex
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
            font.pixelSize: 14
            font.bold: true
          }

          Text {
            text: root.widgetDescription(dialog.workingEntry.id || "")
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: 11
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
        font.pixelSize: 11
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

      Text {
        text: "Horizontal format"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: 11
      }
      TextField {
        text: calForm.entry.format || "dddd HH:mm"
        font.family: root.fontFamily
        font.pixelSize: 12
        width: parent.width
        onEditingFinished: calForm.fieldChanged("format", text)
      }

      Text {
        text: "Alternate format (click to swap)"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: 11
      }
      TextField {
        text: calForm.entry.formatAlt || "dd MMMM 'W'ww yyyy"
        font.family: root.fontFamily
        font.pixelSize: 12
        width: parent.width
        onEditingFinished: calForm.fieldChanged("formatAlt", text)
      }

      Text {
        text: "Vertical format (left/right bars)"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: 11
      }
      TextField {
        text: calForm.entry.verticalFormat || "HH\n—\nmm"
        font.family: root.fontFamily
        font.pixelSize: 12
        width: parent.width
        onEditingFinished: calForm.fieldChanged("verticalFormat", text)
      }
    }
  }

  // ===================== plugins category ==================================
  component PluginManager: Column {
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

    spacing: 14
    Layout.fillWidth: true
    width: parent ? parent.width : 0

    Text {
      text: "Plugins"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: 18
      font.bold: true
    }

    Text {
      text: "Drop plugins at ~/.config/omarchy/plugins/<plugin-id>/, then click Rescan. First-party plugins are always enabled."
      color: Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: 11
      wrapMode: Text.WordWrap
      width: pm.width
    }

    Row {
      spacing: 8
      width: pm.width

      Text {
        text: (root.pluginRegistry ? Object.keys(root.pluginRegistry.installedPlugins).length : 0) + " installed"
        color: Qt.darker(root.foreground, 1.3)
        font.family: root.fontFamily
        font.pixelSize: 11
        anchors.verticalCenter: parent.verticalCenter
      }

      Item { width: Math.max(0, pm.width - 200); height: 1 }

      ActionPill {
        text: "Rescan"
        onClicked: root.pluginRegistry.rescan()
      }
    }

    Repeater {
      model: pm.pluginList()
      delegate: PluginRow {
        required property var modelData
        width: pm.width
        manifest: modelData.manifest
        pluginId: modelData.id
        pluginEnabled: modelData.enabled
        firstParty: modelData.firstParty
      }
    }

    Text {
      visible: pm.pluginList().length === 0
      text: "No plugins discovered yet."
      color: Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: 11
    }
  }

  component PluginRow: Rectangle {
    id: row
    property var manifest: ({})
    property string pluginId: ""
    property bool pluginEnabled: false
    property bool firstParty: false
    property bool expanded: false

    activeFocusOnTab: !row.firstParty
    Keys.onReturnPressed: if (!row.firstParty) root.pluginRegistry.setEnabled(row.pluginId, !row.pluginEnabled)
    Keys.onEnterPressed: if (!row.firstParty) root.pluginRegistry.setEnabled(row.pluginId, !row.pluginEnabled)
    Keys.onSpacePressed: if (!row.firstParty) root.pluginRegistry.setEnabled(row.pluginId, !row.pluginEnabled)

    radius: root.cornerRadius
    color: row.activeFocus
      ? root.focusFillColor
      : (rowArea.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03))
    border.color: row.activeFocus ? root.focusBorderColor : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
    border.width: row.activeFocus ? root.focusBorderWidth : 1
    implicitHeight: rowContent.implicitHeight + 16

    Behavior on color { ColorAnimation { duration: 100 } }

    Column {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 8
      spacing: 4

      Row {
        spacing: 8
        width: parent.width

        Column {
          spacing: 2
          width: parent.width - 110

          Text {
            text: row.manifest && row.manifest.name ? row.manifest.name : row.pluginId
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 12
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }
          Text {
            text: {
              var bits = []
              if (row.manifest && row.manifest.version) bits.push("v" + row.manifest.version)
              if (row.manifest && row.manifest.author) bits.push(row.manifest.author)
              bits.push(row.firstParty ? "first-party" : "third-party")
              return bits.join("  ·  ")
            }
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: 10
          }
          Text {
            visible: !!(row.manifest && row.manifest.description)
            text: row.manifest ? (row.manifest.description || "") : ""
            color: Qt.darker(root.foreground, 1.3)
            font.family: root.fontFamily
            font.pixelSize: 10
            wrapMode: Text.WordWrap
            width: parent.width
          }
        }

        Item { width: 8; height: 1 }

        Item {
          implicitWidth: enabledSwitch.implicitWidth
          implicitHeight: enabledSwitch.implicitHeight
          anchors.verticalCenter: parent.verticalCenter

          Switch {
            id: enabledSwitch
            checked: row.pluginEnabled
            enabled: !row.firstParty
            opacity: row.firstParty ? 0.45 : 1
            ToolTip.visible: row.firstParty && hoverArea.containsMouse
            ToolTip.delay: 300
            ToolTip.text: "First-party plugin — always enabled"
            onToggled: root.pluginRegistry.setEnabled(row.pluginId, checked)
          }

          MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            visible: row.firstParty
            cursorShape: Qt.ForbiddenCursor
          }
        }
      }

      Row {
        visible: !!(row.manifest && row.manifest.barWidget && Array.isArray(row.manifest.barWidget.schema) && row.manifest.barWidget.schema.length > 0)
        spacing: 6

        Text {
          text: row.expanded ? "▾ Options" : "▸ Options"
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: 10

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: row.expanded = !row.expanded
          }
        }
      }

      Repeater {
        model: row.expanded && row.manifest && row.manifest.barWidget && Array.isArray(row.manifest.barWidget.schema) ? row.manifest.barWidget.schema : []
        delegate: Text {
          required property var modelData
          text: "• " + (modelData.label || modelData.key) + " (" + (modelData.type || "string") + ")"
          color: Qt.darker(root.foreground, 1.3)
          font.family: root.fontFamily
          font.pixelSize: 10
          leftPadding: 12
        }
      }
    }

    MouseArea {
      id: rowArea
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }
  }
}
