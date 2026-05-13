import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
  id: root

  property string home: Quickshell.env("HOME")
  function deriveOmarchyPath() {
    var env = Quickshell.env("OMARCHY_PATH")
    if (env) return env
    var dir = String(Quickshell.shellDir || "")
    if (dir.indexOf("/default/quickshell/bar-settings") !== -1)
      return dir.substring(0, dir.indexOf("/default/quickshell/bar-settings"))
    return home + "/.local/share/omarchy"
  }
  property string omarchyPath: deriveOmarchyPath()
  readonly property string userConfigPath: home + "/.config/omarchy/bar.json"
  readonly property string defaultsPath: omarchyPath + "/default/quickshell/bar/bar-defaults.json"

  property color foreground: "#cacccc"
  property color background: "#101315"
  property color accent: "#cacccc"
  property color urgent: "#a55555"

  property string fontFamily: "JetBrainsMono Nerd Font"

  property var defaultConfig: ({})
  property var draft: ({ position: "top", centerAnchor: "calendar", layout: { left: [], center: [], right: [] }, fontFamily: "JetBrainsMono Nerd Font" })
  property var registry: ({})
  property bool dirty: false
  property int draftRevision: 0

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
    try {
      var defaults = defaultsFile.text() ? JSON.parse(defaultsFile.text()) : {}
      defaultConfig = defaults
    } catch (e) {
      console.warn("Bad defaults JSON:", e)
      defaultConfig = {}
    }

    var userText = userFile.text() || "{}"
    var user = {}
    try { user = JSON.parse(userText) } catch (e) { user = {} }

    var merged = mergeConfig(defaultConfig, user)
    draft = {
      position: String(merged.position || "top"),
      centerAnchor: String(merged.centerAnchor || ""),
      fontFamily: String(merged.fontFamily || "JetBrainsMono Nerd Font"),
      layout: normalizeLayout(merged.layout || {})
    }
    dirty = false
    draftRevision++
  }

  function deepEqual(a, b) {
    return JSON.stringify(a) === JSON.stringify(b)
  }

  function diffAgainstDefaults() {
    var defaults = mergeConfig(
      { position: "top", centerAnchor: "", fontFamily: "JetBrainsMono Nerd Font", layout: { left: [], center: [], right: [] } },
      defaultConfig
    )
    var override = {}
    if (!deepEqual(draft.position, defaults.position)) override.position = draft.position
    if (!deepEqual(draft.centerAnchor, defaults.centerAnchor)) override.centerAnchor = draft.centerAnchor
    if (!deepEqual(draft.fontFamily, defaults.fontFamily)) override.fontFamily = draft.fontFamily

    var defaultLayout = normalizeLayout(defaults.layout || {})
    var layoutDiff = {}
    var hasLayoutDiff = false
    var sections = ["left", "center", "right"]
    for (var i = 0; i < sections.length; i++) {
      var s = sections[i]
      if (!deepEqual(draft.layout[s], defaultLayout[s])) {
        layoutDiff[s] = draft.layout[s]
        hasLayoutDiff = true
      }
    }
    if (hasLayoutDiff) override.layout = layoutDiff
    return override
  }

  function saveConfig() {
    var override = diffAgainstDefaults()
    userFile.setText(JSON.stringify(override, null, 2) + "\n")
    dirty = false
  }

  function resetToDefaults() {
    userFile.setText("{}\n")
    loadConfig()
  }

  function markDirty() {
    dirty = true
    draftRevision++
  }

  // Replace the whole `layout` object so any binding that reads `draft.layout`
  // is invalidated. Mutating `draft.layout[section]` alone does not notify QML.
  function mutateLayout(section, mutator) {
    var nextLayout = {
      left: draft.layout.left.slice(),
      center: draft.layout.center.slice(),
      right: draft.layout.right.slice()
    }
    mutator(nextLayout[section])
    var nextDraft = {
      position: draft.position,
      centerAnchor: draft.centerAnchor,
      fontFamily: draft.fontFamily,
      layout: nextLayout
    }
    draft = nextDraft
    markDirty()
  }

  function moveEntry(section, fromIndex, toIndex) {
    if (toIndex < 0 || toIndex >= draft.layout[section].length) return
    mutateLayout(section, function(arr) {
      var item = arr[fromIndex]
      arr.splice(fromIndex, 1)
      arr.splice(toIndex, 0, item)
    })
  }

  function removeEntry(section, index) {
    mutateLayout(section, function(arr) { arr.splice(index, 1) })
  }

  function addEntry(section, id) {
    mutateLayout(section, function(arr) { arr.push({ id: id }) })
  }

  function updateEntry(section, index, newEntry) {
    mutateLayout(section, function(arr) { arr[index] = cloneJson(newEntry) })
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

  // Catalog of available widgets — id → display metadata + settings schema path.
  // settingsForm is an inline-defined Component name that opens when editing.
  readonly property var catalog: ({
    "omarchy":          { name: "Omarchy menu", description: "Launches the Omarchy menu" },
    "workspaces":       { name: "Workspaces (legacy)", description: "Workspace numbers, no animation" },
    "workspacesPro":    { name: "Workspaces", description: "Animated workspace switcher" },
    "activeWindow":     { name: "Active window", description: "Title of the focused window" },
    "clock":            { name: "Clock", description: "Date / time text" },
    "calendar":         { name: "Calendar", description: "Clock with month-grid popup", settingsForm: "calendarSettings" },
    "media":            { name: "Media", description: "MPRIS now-playing with controls" },
    "weather":          { name: "Weather (legacy)", description: "Tiny weather pill" },
    "weatherFlyout":    { name: "Weather", description: "Weather pill with detail popup" },
    "update":           { name: "Updates", description: "Indicates available system updates" },
    "voxtype":          { name: "Voxtype", description: "Voxtype dictation state" },
    "screenRecording":  { name: "Screen recording", description: "Active recording indicator" },
    "idle":             { name: "Idle (legacy)", description: "Inhibitor indicator" },
    "idleInhibitor":    { name: "Keep awake", description: "Idle inhibitor toggle" },
    "notifications":    { name: "DND (mako)", description: "Notification silencing indicator" },
    "notificationCenter": { name: "Notification center", description: "Recent notifications + DND (replaces mako)" },
    "tray":             { name: "System tray", description: "Status notifier items" },
    "bluetooth":        { name: "Bluetooth (legacy)", description: "Bluetooth status icon" },
    "bluetoothPanel":   { name: "Bluetooth", description: "Bluetooth devices popup" },
    "network":          { name: "Network (legacy)", description: "Wi-Fi/ethernet status" },
    "networkPanel":     { name: "Network", description: "Wi-Fi list and connect" },
    "audio":            { name: "Volume (legacy)", description: "Speaker icon, scroll for volume" },
    "audioPanel":       { name: "Volume", description: "Volume slider, output picker, mixer" },
    "microphone":       { name: "Microphone", description: "Mic input state" },
    "nightLight":       { name: "Night light", description: "hyprsunset toggle" },
    "brightness":       { name: "Brightness", description: "Screen brightness slider", settingsForm: "brightnessSettings" },
    "powerProfile":     { name: "Power profile", description: "power-profiles-daemon selector" },
    "battery":          { name: "Battery", description: "Battery percent and ETA" },
    "cpu":              { name: "CPU (legacy)", description: "btop launcher" },
    "systemStats":      { name: "System stats", description: "Inline CPU + RAM graphs" },
    "controlCenter":    { name: "Quick settings", description: "Volume/brightness/DND/etc in one popup" },
    "powerMenu":        { name: "Power menu", description: "Lock/suspend/reboot/shutdown" },
    "keyboardLayout":   { name: "Keyboard layout", description: "Current xkb layout, click cycles" },
    "lockKeys":         { name: "Lock keys", description: "Caps/Num/Scroll lock indicators" },
    "spacer":           { name: "Spacer", description: "Configurable blank space", settingsForm: "spacerSettings" }
  })

  function widgetName(id) {
    return catalog[id] ? catalog[id].name : id
  }

  function widgetDescription(id) {
    return catalog[id] ? (catalog[id].description || "") : ""
  }

  function widgetHasSettings(id) {
    return !!(catalog[id] && catalog[id].settingsForm)
  }

  function availableToAdd(section) {
    var existingByOther = {}
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      if (sections[s] === section) continue
      var list = draft.layout[sections[s]] || []
      for (var i = 0; i < list.length; i++) existingByOther[list[i].id] = true
    }
    var existingHere = {}
    var here = draft.layout[section] || []
    for (var j = 0; j < here.length; j++) existingHere[here[j].id] = true

    var ids = Object.keys(catalog).sort(function(a, b) {
      return widgetName(a).localeCompare(widgetName(b))
    })

    var result = []
    for (var k = 0; k < ids.length; k++) {
      var id = ids[k]
      // Allow multiple instances of `spacer` only.
      var allowMultiple = id === "spacer"
      if (!allowMultiple && existingHere[id]) continue
      result.push({ id: id, name: widgetName(id), description: widgetDescription(id), elsewhere: !!existingByOther[id] })
    }
    return result
  }

  FileView {
    id: defaultsFile
    path: root.defaultsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadConfig()
    onFileChanged: reload()
  }

  FileView {
    id: userFile
    path: root.userConfigPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      if (root.dirty) return
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

            ActionPill {
              text: "Reset to defaults"
              foreground: root.urgent
              onClicked: root.resetToDefaults()
            }

            ActionPill {
              text: root.dirty ? "Save" : "Saved"
              foreground: root.dirty ? root.accent : Qt.darker(root.foreground, 1.5)
              bordered: root.dirty
              onClicked: if (root.dirty) root.saveConfig()
            }
          }
        }

        Row {
          Layout.fillWidth: true
          spacing: 10

          OptionDropdown {
            label: "Position"
            value: root.draft.position
            options: ["top", "right", "bottom", "left"]
            onChanged: function(v) {
              root.draft.position = v
              root.markDirty()
            }
          }

          OptionDropdown {
            label: "Center anchor"
            value: root.draft.centerAnchor
            options: {
              var list = ["(none)"]
              var entries = root.draft.layout.center || []
              for (var i = 0; i < entries.length; i++) list.push(entries[i].id)
              return list
            }
            onChanged: function(v) {
              root.draft.centerAnchor = v === "(none)" ? "" : v
              root.markDirty()
            }
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
          contentHeight: bodyColumn.implicitHeight
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick

          ColumnLayout {
            id: bodyColumn
            width: bodyScroll.width
            spacing: 14

            SectionEditor { sectionKey: "left";   sectionLabel: "Left" }
            SectionEditor { sectionKey: "center"; sectionLabel: "Center" }
            SectionEditor { sectionKey: "right";  sectionLabel: "Right" }
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
    property var entries: (root.draft.layout && root.draft.layout[section.sectionKey]) || []
    Layout.fillWidth: true
    spacing: 8

    Connections {
      target: root
      function onDraftRevisionChanged() { section.entries = (root.draft.layout && root.draft.layout[section.sectionKey]) || [] }
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
            text: modelData.name + (modelData.elsewhere ? "  (elsewhere)" : "")
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

  function formComponent(id) {
    var cat = catalog[id]
    if (!cat || !cat.settingsForm) return null
    switch (cat.settingsForm) {
    case "spacerSettings": return spacerSettingsComponent
    case "calendarSettings": return calendarSettingsComponent
    case "brightnessSettings": return brightnessSettingsComponent
    default: return null
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
}
