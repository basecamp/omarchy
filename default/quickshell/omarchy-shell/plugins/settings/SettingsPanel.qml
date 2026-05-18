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

  // ---------------- theme --------------------------------------------------
  // Bar settings deliberately isn't a themable surface in shell.toml — it
  // tracks the foundational palette so every theme renders consistently.
  property color foreground: Color.foreground
  property color background: Color.background
  property color accent: Color.accent
  property color urgent: Color.urgent
  property string fontFamily: "monospace"

  // Structural style tokens live on the shared Style singleton so toggling
  // `omarchy style corners` and theme swaps update every consumer at once.
  // Aliasing them as readonly properties keeps the existing inline component
  // bindings (`root.cornerRadius`, `root.focusBorderColor`, ...) working
  // without sprinkling Style.* across the file.
  readonly property int cornerRadius: Style.cornerRadius
  readonly property color focusBorderColor: Style.focusBorderColor
  readonly property color focusFillColor: Style.focusFillColor
  readonly property int focusBorderWidth: Style.focusBorderWidth

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
  // `activeFocusOnTab: true` so j/k can move through the form.
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
    if (items.length === 0) { parkFocusOnSink(); return }
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

  // ---------------- bundled defaults ---------------------------------------
  readonly property var builtinShellConfig: ({
    version: 1,
    bar: {
      position: "top",
      transparent: false,
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
          { id: "monitorPanel" }, { id: "battery" }
        ]
      }
    },
    plugins: []
  })

  property var defaultConfig: builtinShellConfig
  property var draft: ({ version: 1, bar: { position: "top", transparent: false, centerAnchor: "calendar", layout: { left: [], center: [], right: [] } }, plugins: [] })
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
        transparent: bar.transparent === true,
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

  function defaultBarDraft() {
    var source = defaultConfig
    if (!isPlainObject(source) || !isPlainObject(source.bar) || !isPlainObject(source.bar.layout)) {
      source = builtinShellConfig
    } else {
      var l = source.bar.layout
      var anyEntries = (l.left && l.left.length) || (l.center && l.center.length) || (l.right && l.right.length)
      if (!anyEntries) source = builtinShellConfig
    }
    return normalizeDraft(source).bar
  }

  function resetBarToDefaults() {
    var next = cloneJson(draft)
    next.bar = cloneJson(defaultBarDraft())
    draft = next
    draftRevision++
    persistDraft()
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
    console.log("bar settings panel open. omarchyPath=" + root.omarchyPath,
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
        category: meta.category || "Plugin",
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
    return false
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
    var barSections = ["left", "center", "right"]

    var existingInBar = {}
    for (var s = 0; s < barSections.length; s++) {
      var list = sectionArray(barSections[s])
      for (var i = 0; i < list.length; i++) existingInBar[list[i].id] = true
    }

    var ids = catalogIds().sort(function(a, b) { return widgetName(a).localeCompare(widgetName(b)) })

    var result = []
    for (var k = 0; k < ids.length; k++) {
      var id = ids[k]
      var meta = widgetMetadata(id)
      var manifest = root.pluginRegistry ? root.pluginRegistry.installedPlugins[id] : null
      var manifestIsBarWidget = manifest && Array.isArray(manifest.kinds) && manifest.kinds.indexOf("bar-widget") !== -1
      var isBarWidget = !!(meta && meta.source !== "plugin") || manifestIsBarWidget
      if (!isBarWidget && !legacyWidgetMeta[id]) continue

      var inSection = sectionArray(section)
      var existsHere = false
      for (var x = 0; x < inSection.length; x++) if (inSection[x].id === id) { existsHere = true; break }
      var allowsMultiple = widgetAllowsMultiple(id)
      if (!allowsMultiple && existingInBar[id]) continue
      result.push({ id: id, name: widgetName(id), description: widgetDescription(id),
        elsewhere: allowsMultiple && !!existingInBar[id] && !existsHere })
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

  // ---------------- window -------------------------------------------------
  FloatingWindow {
    id: window
    title: "Omarchy Bar Settings"
    color: root.background
    implicitWidth: 760
    implicitHeight: 620
    minimumSize: Qt.size(620, 480)

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

      // Invisible focus sink. When no specific body item is focused,
      // activeFocus lives on this 1px Item so body controls render their
      // unfocused state cleanly.
      Item {
        id: navFocusSink
        width: 1
        height: 1
        objectName: "navFocusSink"
      }

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        switch (event.key) {
        case Qt.Key_Escape:
          root.close(); event.accepted = true; return
        case Qt.Key_J:
        case Qt.Key_Down:
        case Qt.Key_Tab:
          root.focusBodyDelta(+1); event.accepted = true; return
        case Qt.Key_K:
        case Qt.Key_Up:
        case Qt.Key_Backtab:
          root.focusBodyDelta(-1); event.accepted = true; return
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
            text: "Omarchy Bar Settings"
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

        // Content
        Flickable {
          id: bodyScroll
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.margins: 18
          clip: true
          contentWidth: width
          contentHeight: contentColumn.implicitHeight
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick

          ColumnLayout {
            id: contentColumn
            width: bodyScroll.width
            spacing: 14

            BarCategory { Layout.fillWidth: true }
          }
        }
      }
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

      PositionButtonGroup {
        value: root.draft.bar.position
        onChanged: function(v) {
          if (root.draft.bar.position === v) return
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

    BarToggleRow {
      Layout.fillWidth: true
      label: "Transparent bar"
      description: "Hide the bar background so the wallpaper shows through."
      checked: root.draft.bar.transparent === true
      onClicked: {
        var next = root.cloneJson(root.draft)
        next.bar.transparent = !(next.bar.transparent === true)
        root.draft = next
        root.markDirty()
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
        text: "Reset bar to defaults"
        foreground: root.urgent
        onClicked: root.resetBarToDefaults()
      }
    }
  }

  // ===================== shared chrome =====================================
  component PositionButtonGroup: Item {
    id: positionGroup

    property string value: "top"
    readonly property var positions: ["top", "right", "bottom", "left"]

    signal changed(string value)

    implicitWidth: positionColumn.implicitWidth
    implicitHeight: positionColumn.implicitHeight

    Column {
      id: positionColumn
      spacing: 4

      Text {
        text: "Position"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: 10
        font.bold: true
      }

      Row {
        spacing: 6

        Repeater {
          model: positionGroup.positions

          delegate: PositionButton {
            required property string modelData

            text: modelData
            selected: positionGroup.value === modelData
            onClicked: positionGroup.changed(modelData)
          }
        }
      }
    }
  }

  component PositionButton: Rectangle {
    id: positionButton

    property string text: ""
    property bool selected: false

    signal clicked()

    activeFocusOnTab: true
    Keys.onReturnPressed: positionButton.clicked()
    Keys.onEnterPressed: positionButton.clicked()
    Keys.onSpacePressed: positionButton.clicked()

    implicitWidth: Math.max(56, positionLabel.implicitWidth + 22)
    implicitHeight: 28
    radius: root.cornerRadius
    color: positionButton.selected
      ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
      : (positionArea.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : root.background)
    border.color: positionButton.selected
      ? root.accent
      : (positionButton.activeFocus ? root.foreground : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.4))
    border.width: positionButton.selected ? 2 : (positionButton.activeFocus ? 2 : 1)

    Behavior on color { ColorAnimation { duration: 100 } }

    Text {
      id: positionLabel
      anchors.centerIn: parent
      text: positionButton.text
      color: positionButton.selected ? root.accent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: 12
      font.bold: positionButton.selected
    }

    MouseArea {
      id: positionArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        positionButton.forceActiveFocus()
        positionButton.clicked()
      }
    }
  }

  component BarToggleRow: Rectangle {
    id: toggleRow

    property string label: ""
    property string description: ""
    property bool checked: false

    signal clicked()

    activeFocusOnTab: true
    Keys.onReturnPressed: toggleRow.clicked()
    Keys.onEnterPressed: toggleRow.clicked()
    Keys.onSpacePressed: toggleRow.clicked()

    Layout.fillWidth: true
    implicitHeight: Math.max(54, toggleContent.implicitHeight + 18)
    radius: root.cornerRadius
    color: toggleRow.activeFocus
      ? root.focusFillColor
      : (toggleArea.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03))
    border.color: toggleRow.activeFocus ? root.focusBorderColor : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
    border.width: toggleRow.activeFocus ? root.focusBorderWidth : 1

    Behavior on color { ColorAnimation { duration: 100 } }

    Row {
      id: toggleContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: 12
      spacing: 12

      Column {
        width: parent.width - switchTrack.width - parent.spacing
        spacing: 3
        anchors.verticalCenter: parent.verticalCenter

        Text {
          text: toggleRow.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: 13
          font.bold: true
          elide: Text.ElideRight
          width: parent.width
        }

        Text {
          text: toggleRow.description
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: 10
          wrapMode: Text.WordWrap
          width: parent.width
        }
      }

      Rectangle {
        id: switchTrack
        width: 42
        height: 22
        radius: height / 2
        color: toggleRow.checked
          ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)
          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
        border.color: toggleRow.checked ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.28)
        border.width: 1
        anchors.verticalCenter: parent.verticalCenter

        Behavior on color { ColorAnimation { duration: 120 } }

        Rectangle {
          width: 16
          height: 16
          radius: 8
          x: toggleRow.checked ? switchTrack.width - width - 3 : 3
          y: 3
          color: toggleRow.checked ? root.accent : Qt.darker(root.foreground, 1.25)

          Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
          Behavior on color { ColorAnimation { duration: 120 } }
        }
      }
    }

    MouseArea {
      id: toggleArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: toggleRow.clicked()
    }
  }

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
      case "weatherSettings": return weatherSettingsComponent
      }
    }
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

      component CalendarField: TextField {
        id: calField
        property string fieldKey: ""
        font.family: root.fontFamily
        font.pixelSize: 12
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
        font.pixelSize: 11
      }
      CalendarField {
        fieldKey: "format"
        text: calForm.entry.format || "dddd HH:mm"
      }

      Text {
        text: "Alternate format (click to swap)"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: 11
      }
      CalendarField {
        fieldKey: "formatAlt"
        text: calForm.entry.formatAlt || "dd MMMM 'W'ww yyyy"
      }

      Text {
        text: "Vertical format (left/right bars)"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: 11
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
        font.pixelSize: 11
      }

      SpinBox {
        from: 1
        to: 1440
        value: weatherForm.entry.refreshMinutes !== undefined ? weatherForm.entry.refreshMinutes : 15
        onValueModified: weatherForm.fieldChanged("refreshMinutes", value)
      }
    }
  }


}
