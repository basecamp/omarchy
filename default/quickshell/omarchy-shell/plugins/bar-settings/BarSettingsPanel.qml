import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import "../../ui/settings" as SettingsUi

Item {
  id: root

  // Plugin lifecycle hooks. omarchy-shell calls open(payloadJson) on summon
  // and close() on hide. We don't consume payloads yet, and visibility is
  // driven by the host Loader's `active`, so both are no-ops for now.
  function open(payloadJson) { /* no payload schema yet; reserved for future use */ }
  function close() { /* visibility handled by parent Loader; nothing to clean up */ }

  // Injected by the host shell when the panel is summoned. Shared instances
  // so the panel sees the same registry state the bar wrote into.
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  // The host shell. Used to look up pluginApi for Noctalia plugins so their
  // Settings.qml can read/write via pluginApi.saveSettings().
  property var shell: null

  // Not `required` so the Loader-based instantiation can satisfy it via
  // onLoaded; we still gracefully fall back to deriving from shellDir for
  // standalone QML tooling.
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

  property color foreground: "#cacccc"
  property color background: "#101315"
  property color accent: "#cacccc"
  property color urgent: "#a55555"

  property string fontFamily: "JetBrainsMono Nerd Font"
  property string activeTab: "layout"

  // Bundled fallback so 'Reset to defaults' never produces an empty config
  // even if shell-defaults.json fails to load. Keep in rough sync with the
  // file shipped at default/quickshell/omarchy-shell/shell-defaults.json.
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
          { id: "nightLight" }, { id: "brightness" }, { id: "powerProfile" },
          { id: "battery" }, { id: "controlCenter" }, { id: "powerMenu" }
        ]
      }
    },
    plugins: []
  })

  property var defaultConfig: builtinShellConfig
  // The draft mirrors the full shell.json on-disk shape. Editors operate on
  // draft.bar.layout.* and draft.plugins; the file we persist is `draft`.
  property var draft: ({ version: 1, bar: { position: "top", centerAnchor: "calendar", fontFamily: "JetBrainsMono Nerd Font", layout: { left: [], center: [], right: [] } }, plugins: [] })
  property var registry: ({})
  property int draftRevision: 0
  property bool suppressReload: false

  function cloneJson(value) {
    return JSON.parse(JSON.stringify(value || null))
  }

  function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
  }

  function mergeConfig(base, override) {
    var result = cloneJson(base || {})
    if (!isPlainObject(override)) return result
    for (var key in override) {
      if (isPlainObject(result[key]) && isPlainObject(override[key]))
        result[key] = mergeConfig(result[key], override[key])
      else
        result[key] = cloneJson(override[key])
    }
    return result
  }

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

    // shell.json is canonical when present and valid; otherwise we fall back
    // to defaults. We do NOT deep-merge — once the user has a shell.json, the
    // file's contents are authoritative.
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
          // Drop first-party panel/overlay/menu plugins from the user's
          // plugins[] — they're shell infrastructure, summon-on-demand,
          // and don't belong in user-editable lists.
          var manifest = root.pluginRegistry ? root.pluginRegistry.installedPlugins[e.id] : null
          if (manifest && manifest.__isFirstParty) return false
          return true
        })
    }
  }

  function persistDraft() {
    // Suppress the inotify callback that this write triggers so the FileView
    // reload doesn't race with rapid edits and clobber them.
    suppressReload = true
    userFile.setText(JSON.stringify(draft, null, 2) + "\n")
  }

  function resetToDefaults() {
    // Always fall back to the bundled builtin if defaultConfig wound up empty
    // (path resolution failed or defaultsFile hasn't finished loading), so
    // Reset never zeroes the bar out.
    var source = defaultConfig
    if (!isPlainObject(source) || !isPlainObject(source.bar) || !isPlainObject(source.bar.layout)) {
      source = builtinShellConfig
    } else {
      var l = source.bar.layout
      var anyEntries = (l.left && l.left.length) || (l.center && l.center.length) || (l.right && l.right.length)
      if (!anyEntries) source = builtinShellConfig
    }
    var payload = normalizeDraft(source)
    // Update the GUI synchronously — the suppressed file-watch callback won't
    // fire loadConfig, so the draft would otherwise stay stale.
    draft = payload
    draftRevision++
    suppressReload = true
    userFile.setText(JSON.stringify(payload, null, 2) + "\n")
  }

  function markDirty() {
    draftRevision++
    persistDraft()
  }

  // Section list helpers operate on a virtual section name. "left" / "center"
  // / "right" address draft.bar.layout.<section>; "plugins" addresses
  // draft.plugins. The mutators replace the whole `draft` so any binding that
  // reads it re-evaluates.
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

  // Catalog is derived live from BarWidgetRegistry (first-party + third-party
  // plugin widgets registered at runtime) plus a small legacy descriptor map
  // for builtins that Bar.qml renders inline via builtinModuleComponent and
  // hasn't migrated into the registry yet. The merged catalog is rebuilt
  // whenever the registry revision changes.
  readonly property var legacyWidgetMeta: ({
    "omarchy":          { name: "Omarchy menu",      description: "Launches the Omarchy menu",                category: "Compositor" },
    "workspaces":       { name: "Workspaces",          description: "Workspace number indicators",              category: "Compositor" },
    "clock":            { name: "Clock",             description: "Date / time text",                          category: "Time" },
    "weather":          { name: "Weather (legacy)", description: "Tiny weather pill",                          category: "Info" },
    "update":           { name: "Updates",           description: "Indicates available system updates",        category: "System" },
    "voxtype":          { name: "Voxtype",           description: "Voxtype dictation state",                   category: "Status" },
    "screenRecording":  { name: "Screen recording",  description: "Active recording indicator",                category: "Status" },
    "idle":             { name: "Idle (legacy)",    description: "Inhibitor indicator",                        category: "Status" },
    "notifications":    { name: "DND (mako)",        description: "Notification silencing indicator",          category: "Status" },
    "tray":             { name: "System tray",       description: "Status notifier items",                     category: "Status" },
    "bluetooth":        { name: "Bluetooth (legacy)", description: "Bluetooth status icon",                    category: "Network" },
    "network":          { name: "Network (legacy)", description: "Wi-Fi / ethernet status",                    category: "Network" },
    "audio":            { name: "Volume (legacy)", description: "Speaker icon, scroll for volume",            category: "Audio" },
    "cpu":              { name: "CPU (legacy)",     description: "btop launcher",                              category: "System" },
    "battery":          { name: "Battery",           description: "Battery percent and ETA",                   category: "System" }
  })

  property int catalogRevision: 0
  // Bump on every registry assignment (including the initial null → instance
  // injection from Loader.onLoaded) so bindings that derive from
  // widgetMetadata pick up the new state. The host injects the registry
  // asynchronously via the Loader, so we also log once it lands.
  onBarWidgetRegistryChanged: {
    catalogRevision++
    if (!root.barWidgetRegistry) return
    console.log("bar-settings open. omarchyPath=" + root.omarchyPath,
      "defaultsPath=" + root.defaultsPath,
      "userConfigPath=" + root.userConfigPath,
      "registry has",
      root.barWidgetRegistry.availableIds().length,
      "widgets")
  }
  Connections {
    target: root.barWidgetRegistry
    function onChanged() {
      root.catalogRevision++
    }
  }


  function widgetMetadata(id) {
    var key = String(id || "")
    if (root.barWidgetRegistry && root.barWidgetRegistry.has(key))
      return root.barWidgetRegistry.metadataFor(key) || {}
    if (legacyWidgetMeta[key]) return legacyWidgetMeta[key]
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
    // Noctalia plugins ship their own Settings.qml — surface the gear icon
    // even though we don't render a built-in form for them.
    var manifest = root.pluginRegistry ? root.pluginRegistry.installedPlugins[id] : null
    if (manifest && manifest.__noctaliaCompat && manifest.entryPoints && manifest.entryPoints.settings)
      return true
    return false
  }

  function widgetIsPlugin(id) {
    var meta = widgetMetadata(id)
    return meta.source === "plugin"
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
    for (var key in legacyWidgetMeta) ids[key] = true
    return Object.keys(ids)
  }

  // section is one of "left" / "center" / "right" for bar widgets, or
  // "plugins" for the non-bar plugin list. The catalogue we offer differs:
  // bar sections accept anything with kind `bar-widget` (or anything in the
  // legacy widget metadata); the plugins section accepts panel/overlay/menu/
  // service kinds.
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

    var ids = catalogIds().sort(function(a, b) {
      return widgetName(a).localeCompare(widgetName(b))
    })

    var result = []
    for (var k = 0; k < ids.length; k++) {
      var id = ids[k]
      var meta = widgetMetadata(id)
      var isBarWidget = !!(meta && meta.source !== "plugin")
        || (meta && meta.kinds && meta.kinds.indexOf && meta.kinds.indexOf("bar-widget") !== -1)
      if (isBarSection) {
        if (!isBarWidget && !legacyWidgetMeta[id]) continue
        var inSection = sectionArray(section)
        var existsHere = false
        for (var x = 0; x < inSection.length; x++) if (inSection[x].id === id) { existsHere = true; break }
        var allowsMultiple = widgetAllowsMultiple(id)
        // Hard block: if it's already placed in any bar section and the
        // widget doesn't permit multiple instances, drop it from the menu
        // entirely rather than offer an "(elsewhere)" entry that would
        // silently move/duplicate state.
        if (!allowsMultiple && existingInBar[id]) continue
        // For widgets that do allow multiple (spacer), the `elsewhere`
        // hint is informational only.
        result.push({ id: id, name: widgetName(id), description: widgetDescription(id),
          elsewhere: allowsMultiple && !!existingInBar[id] && !existsHere,
          isNoctalia: widgetIsNoctaliaPlugin(id) })
      } else {
        // Plugins section: accept third-party plugins with any non-bar kind.
        // First-party panels/overlays (bar-settings, image-picker) are
        // shell infrastructure and don't belong in user-editable lists.
        var manifest = root.pluginRegistry ? root.pluginRegistry.installedPlugins[id] : null
        if (!manifest) continue
        if (manifest.__isFirstParty) continue
        if (existingInPlugins[id]) continue
        result.push({ id: id, name: widgetName(id), description: widgetDescription(id), elsewhere: false,
          isNoctalia: widgetIsNoctaliaPlugin(id) })
      }
    }
    return result
  }

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
      if (root.suppressReload) {
        root.suppressReload = false
        return
      }
      root.loadConfig()
    }
    onFileChanged: reload()
  }

  FileView {
    path: root.home + "/.config/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadTheme(text())
    onFileChanged: reload()
  }

  FloatingWindow {
    id: window
    title: "Omarchy bar settings"
    color: root.background
    implicitWidth: 720
    implicitHeight: 720
    minimumSize: Qt.size(560, 500)

    Rectangle {
      anchors.fill: parent
      color: root.background

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        Item {
          Layout.fillWidth: true
          implicitHeight: 32

          Text {
            text: "Bar settings"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 20
            font.bold: true
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Row {
            spacing: 8
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Text {
              text: "Auto-saving to ~/.config/omarchy/shell.json"
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 11
              anchors.verticalCenter: parent.verticalCenter
            }

            ActionPill {
              text: "Reset to defaults"
              foreground: root.urgent
              onClicked: root.resetToDefaults()
            }
          }
        }

        Row {
          Layout.fillWidth: true
          spacing: 10

          OptionDropdown {
            label: "Position"
            value: root.draft.bar.position
            options: ["top", "right", "bottom", "left"]
            onChanged: function(v) {
              var next = root.cloneJson(root.draft)
              next.bar.position = v
              root.draft = next
              root.markDirty()
            }
          }

          OptionDropdown {
            label: "Center anchor"
            value: root.draft.bar.centerAnchor
            options: {
              var list = ["(none)"]
              var entries = root.draft.bar.layout.center || []
              for (var i = 0; i < entries.length; i++) list.push(entries[i].id)
              return list
            }
            onChanged: function(v) {
              var next = root.cloneJson(root.draft)
              next.bar.centerAnchor = v === "(none)" ? "" : v
              root.draft = next
              root.markDirty()
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          height: 1
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
        }

        Row {
          Layout.fillWidth: true
          spacing: 0

          TabButton {
            label: "Layout"
            selected: root.activeTab === "layout"
            onClicked: root.activeTab = "layout"
          }
          TabButton {
            label: "Plugins"
            selected: root.activeTab === "plugins"
            onClicked: root.activeTab = "plugins"
          }
        }

        Rectangle {
          Layout.fillWidth: true
          height: 1
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
        }

        Flickable {
          id: bodyScroll
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          contentWidth: width
          contentHeight: activeTabContent.implicitHeight
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick

          ColumnLayout {
            id: activeTabContent
            width: bodyScroll.width
            spacing: 14

            ColumnLayout {
              visible: root.activeTab === "layout"
              Layout.fillWidth: true
              spacing: 14

              SectionEditor { sectionKey: "left";   sectionLabel: "Bar · Left" }
              SectionEditor { sectionKey: "center"; sectionLabel: "Bar · Center" }
              SectionEditor { sectionKey: "right";  sectionLabel: "Bar · Right" }

              Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
              }

              SectionEditor { sectionKey: "plugins"; sectionLabel: "Other plugins" }
            }

            PluginManager {
              visible: root.activeTab === "plugins"
              Layout.fillWidth: true
            }
          }
        }
      }
    }
  }

  // ---------- Components ---------------------------------------------------

  component ActionPill: Rectangle {
    id: pill
    property string text: ""
    property color foreground: root.foreground
    property bool bordered: true
    signal clicked()

    implicitWidth: pillLabel.implicitWidth + 22
    implicitHeight: 26
    radius: 4
    color: pillArea.containsMouse ? Qt.rgba(pill.foreground.r, pill.foreground.g, pill.foreground.b, 0.15) : "transparent"
    border.color: pill.bordered ? pill.foreground : "transparent"
    border.width: 1

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

  component OptionDropdown: Item {
    id: dropdown
    property string label: ""
    property string value: ""
    property var options: []
    signal changed(string value)

    implicitWidth: 240
    implicitHeight: 48

    Column {
      anchors.fill: parent
      spacing: 4

      Text {
        text: dropdown.label
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: 10
        font.bold: true
      }

      ComboBox {
        id: combo
        width: parent.width
        height: 28
        font.family: root.fontFamily
        font.pixelSize: 11
        model: dropdown.options
        currentIndex: {
          for (var i = 0; i < model.length; i++) if (model[i] === dropdown.value) return i
          return 0
        }

        onActivated: function(index) {
          dropdown.changed(model[index])
        }

        background: Rectangle {
          color: root.background
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.4)
          border.width: 1
          radius: 4
        }

        contentItem: Text {
          leftPadding: 8
          rightPadding: 24
          text: combo.displayText
          color: root.foreground
          font: combo.font
          verticalAlignment: Text.AlignVCenter
        }
      }
    }
  }

  component SectionEditor: Column {
    id: section

    property string sectionKey: ""
    property string sectionLabel: ""
    property var entries: root.sectionArray(section.sectionKey)
    Layout.fillWidth: true
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
        font.pixelSize: 14
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

      Item { width: section.width - 200 - parent.children[0].implicitWidth - parent.children[1].implicitWidth; height: 1 }

      ActionPill {
        text: "+ Add widget"
        onClicked: addMenu.popup()
      }

      Menu {
        id: addMenu
        Repeater {
          model: root.availableToAdd(section.sectionKey)
          delegate: MenuItem {
            required property var modelData
            // Suffix order matches what users skim left-to-right:
            // name first, origin badge, then "elsewhere" if shared across sections.
            text: modelData.name
              + (modelData.isNoctalia ? "  (Noctalia)" : "")
              + (modelData.elsewhere ? "  (elsewhere)" : "")
            onTriggered: root.addEntry(section.sectionKey, modelData.id)
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
        radius: 4
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
    radius: 4
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

  component IconButton: Rectangle {
    id: iconButton
    property string glyph: ""
    property string tooltip: ""
    property color foreground: root.foreground
    signal clicked()

    implicitWidth: 26
    implicitHeight: 26
    radius: 3
    color: iconArea.containsMouse ? Qt.rgba(iconButton.foreground.r, iconButton.foreground.g, iconButton.foreground.b, 0.18) : "transparent"

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
      root.updateEntry(sectionKey, entryIndex, workingEntry)
      win.visible = false
    }

    function discard() {
      win.visible = false
    }

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

  // Resolution order:
  //   1) First-party inline forms (id-keyed switch).
  //   2) Noctalia plugin's own Settings.qml — we load it inside a Loader
  //      so the plugin renders its native UI and writes via pluginApi.
  //   3) Generic DynamicSettingsForm built from manifest schema entries.
  function formComponent(id) {
    var meta = widgetMetadata(id)
    if (meta && meta.settingsForm) {
      switch (meta.settingsForm) {
      case "spacerSettings": return spacerSettingsComponent
      case "calendarSettings": return calendarSettingsComponent
      case "brightnessSettings": return brightnessSettingsComponent
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

  // Loader stub for Noctalia plugins that bundle a Settings.qml. We load the
  // plugin's form and inject pluginApi so the plugin's own "save" button
  // routes through pluginApi.saveSettings() — which lands in shell.json via
  // shell.updateEntryInline. The plugin form doesn't emit `fieldChanged`,
  // so the dialog's Apply/Cancel buttons are mostly decorative for these
  // (writes already happened by the time you click Apply).
  Component {
    id: noctaliaSettingsComponent

    Item {
      id: noctaliaForm
      property var entry: ({})
      property string pluginId: entry && entry.id ? String(entry.id) : ""
      property var manifest: pluginId && root.pluginRegistry
        ? root.pluginRegistry.installedPlugins[pluginId] : null

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

  Component {
    id: brightnessSettingsComponent

    Column {
      id: brightForm
      signal fieldChanged(string key, var value)
      property var entry: ({})

      spacing: 8
      width: parent ? parent.width : 0

      Text {
        text: "Scroll step (% per notch)"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: 11
      }
      SpinBox {
        from: 1
        to: 25
        value: brightForm.entry.step !== undefined ? brightForm.entry.step : 5
        onValueModified: brightForm.fieldChanged("step", value)
      }
    }
  }

  component TabButton: Rectangle {
    id: tab
    property string label: ""
    property bool selected: false
    signal clicked()

    implicitWidth: tabLabel.implicitWidth + 28
    implicitHeight: 32
    color: tabArea.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"

    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
      id: tabLabel
      anchors.centerIn: parent
      text: tab.label
      color: tab.selected ? root.foreground : Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: 12
      font.bold: tab.selected
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 2
      color: tab.selected ? root.foreground : "transparent"
    }

    MouseArea {
      id: tabArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tab.clicked()
    }
  }

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

    spacing: 10
    width: parent ? parent.width : 0

    Row {
      spacing: 8
      width: parent.width

      Text {
        text: "Plugins"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 14
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: "·  " + (root.pluginRegistry ? Object.keys(root.pluginRegistry.installedPlugins).length : 0) + " installed"
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: 11
        anchors.verticalCenter: parent.verticalCenter
      }

      Item { width: parent.width - 280; height: 1 }

      ActionPill {
        text: "Rescan"
        onClicked: root.pluginRegistry.rescan()
      }
    }

    Text {
      text: "Drop plugins at ~/.config/omarchy/plugins/<plugin-id>/"
      color: Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: 10
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

    radius: 4
    color: rowArea.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
    border.width: 1
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

          // Switch.enabled=false also disables mouse tracking, so the tooltip
          // never sees a hover event. Layer a transparent hover-only MouseArea
          // on top to surface the explanation.
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
