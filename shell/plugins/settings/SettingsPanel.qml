import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

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
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  readonly property string home: Quickshell.env("HOME")
  readonly property string userConfigPath: home + "/.config/omarchy/shell.json"
  readonly property string defaultsPath: omarchyPath + "/shell/shell-defaults.json"

  // ---------------- theme --------------------------------------------------
  // Bar settings deliberately isn't a themable surface in shell.toml — it
  // tracks the foundational palette so every theme renders consistently.
  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color accent: Color.accent
  property color urgent: Color.urgent
  property string fontFamily: "monospace"

  // Structural style tokens live on the shared Style singleton so theme swaps
  // and Hyprland-derived values update every consumer at once.
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
    var pad = Style.space(24)
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
      centerAnchor: "Clock",
      layout: {
        left: [{ id: "Omarchy" }, { id: "Workspaces" }],
        center: [
          { id: "Clock", format: "dddd HH:mm", formatAlt: "dd MMMM 'W'ww yyyy", verticalFormat: "HH\n\u2014\nmm" },
          { id: "Weather" }, { id: "Indicators", items: [ "Dnd", "NightLight", "StayAwake", "ScreenRecording", "Dictation" ] }, { id: "SystemUpdate" }
        ],
        right: [
          { id: "Tray" }, { id: "BluetoothPanel" }, { id: "NetworkPanel" },
          { id: "AudioPanel" }, { id: "MonitorPanel" }, { id: "PowerPanel" }
        ]
      }
    },
    plugins: []
  })

  property var defaultConfig: builtinShellConfig
  property var draft: ({ version: 1, bar: { position: "top", transparent: false, centerAnchor: "Clock", layout: { left: [], center: [], right: [] } }, plugins: [] })
  property int draftRevision: 0
  property bool suppressReload: false

  // When a widget action moves an entry, the Repeater rebuilds / reindexes
  // cards. Remember the action group position so focus follows the moved
  // widget instead of falling back to the first action on the old/new row.
  property string pendingActionFocusSection: ""
  property int pendingActionFocusIndex: -1
  property int pendingActionFocusAction: 0
  property int pendingActionFocusRevision: 0

  function scheduleActionFocus(section, index, action) {
    pendingActionFocusSection = section
    pendingActionFocusIndex = index
    pendingActionFocusAction = action
    pendingActionFocusRevision++
  }

  function clearPendingActionFocus() {
    pendingActionFocusSection = ""
    pendingActionFocusIndex = -1
    pendingActionFocusAction = 0
  }

  // ---------------- draft helpers ------------------------------------------
  function normalizeDraft(source) {
    var bar = Util.isPlainObject(source.bar) ? source.bar : {}
    var plugins = Array.isArray(source.plugins) ? source.plugins.slice() : []
    return {
      version: 1,
      bar: {
        position: String(bar.position || "top"),
        transparent: bar.transparent === true,
        centerAnchor: String(bar.centerAnchor || ""),
        layout: Util.normalizeLayout(bar.layout || {})
      },
      plugins: plugins
        .map(Util.normalizeLayoutEntry)
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
        if (Util.isPlainObject(parsed) && parsed.version === 1) defaults = parsed
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
        if (Util.isPlainObject(u) && u.version === 1) source = u
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
    if (!Util.isPlainObject(source) || !Util.isPlainObject(source.bar) || !Util.isPlainObject(source.bar.layout)) {
      source = builtinShellConfig
    } else {
      var l = source.bar.layout
      var anyEntries = (l.left && l.left.length) || (l.center && l.center.length) || (l.right && l.right.length)
      if (!anyEntries) source = builtinShellConfig
    }
    return normalizeDraft(source).bar
  }

  function resetBarToDefaults() {
    var next = Util.cloneJson(draft)
    next.bar = Util.cloneJson(defaultBarDraft())
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
    var nextDraft = Util.cloneJson(draft)
    if (section === "plugins") nextDraft.plugins = arr
    else nextDraft.bar.layout[section] = arr
    draft = nextDraft
    markDirty()
  }

  function moveEntry(section, fromIndex, toIndex, focusActionIndex) {
    var arr = sectionArray(section)
    if (toIndex < 0 || toIndex >= arr.length) return
    mutateSection(section, function(a) {
      var item = a[fromIndex]
      a.splice(fromIndex, 1)
      a.splice(toIndex, 0, item)
    })
    if (focusActionIndex !== undefined) scheduleActionFocus(section, toIndex, focusActionIndex)
  }

  function removeEntry(section, index) {
    mutateSection(section, function(a) { a.splice(index, 1) })
  }

  function addEntry(section, id) {
    mutateSection(section, function(a) { a.push({ id: id }) })
  }

  function updateEntry(section, index, newEntry) {
    mutateSection(section, function(a) { a[index] = Util.cloneJson(newEntry) })
  }

  // ---------------- widget catalog -----------------------------------------
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

  function canonicalWidgetId(id) {
    return String(id || "")
  }

  function widgetMetadata(id) {
    var key = String(id || "")
    var canonicalKey = canonicalWidgetId(key)
    if (root.barWidgetRegistry && root.barWidgetRegistry.has(canonicalKey))
      return root.barWidgetRegistry.metadataFor(canonicalKey) || {}

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
    return String(id) === "Spacer"
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
      if (!isBarWidget) continue

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
  // ---------------- per-widget settings dialog state -----------------------
  property bool widgetDialogVisible: false
  property string widgetDialogSection: ""
  property int widgetDialogIndex: -1
  property var widgetDialogEntry: ({})

  function openWidgetSettings(sectionKey, entryIndex, entry) {
    widgetDialogEntry = Util.cloneJson(entry)
    widgetDialogSection = sectionKey
    widgetDialogIndex = entryIndex
    widgetDialogVisible = true
  }

  function commitWidgetSettings() {
    if (widgetDialogFormLoader.item && typeof widgetDialogFormLoader.item.saveSettings === "function") {
      widgetDialogFormLoader.item.saveSettings()
    } else {
      root.updateEntry(widgetDialogSection, widgetDialogIndex, widgetDialogEntry)
    }
    widgetDialogVisible = false
  }

  function discardWidgetSettings() { widgetDialogVisible = false }

  function widgetDialogFieldChanged(key, value) {
    var copy = Util.cloneJson(widgetDialogEntry)
    copy[key] = value
    widgetDialogEntry = copy
  }

  FloatingWindow {
    id: window
    title: "Omarchy Bar Settings"
    color: root.background
    implicitWidth: Style.space(760)
    implicitHeight: Style.space(620)
    minimumSize: Qt.size(Style.space(620), Style.space(480))

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
            Layout.preferredHeight: Math.max(Style.space(48), Style.font.heading + Style.spacing.controlPaddingY * 2)

            Text {
              text: "Omarchy Bar Settings"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.panelPadding
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: "~/.config/omarchy/shell.json"
              color: Qt.darker(root.foreground, 1.8)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.panelPadding
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.spacing.hairline
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
          }

          // Content
          Flickable {
            id: bodyScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Style.spacing.panelPadding
            clip: true
            contentWidth: width
            contentHeight: contentColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            ColumnLayout {
              id: contentColumn
              width: bodyScroll.width
              spacing: Style.spacing.panelGap

              BarCategory { Layout.fillWidth: true }
            }
          }
        }
      }
    }

    // ---------- per-widget settings overlay -----------------------------------
    Rectangle {
      anchors.fill: parent
      visible: root.widgetDialogVisible
      color: Qt.rgba(0, 0, 0, 0.45)
      z: 100

      focus: visible
      onVisibleChanged: if (visible) Qt.callLater(forceActiveFocus)

      MouseArea {
        anchors.fill: parent
        onClicked: root.discardWidgetSettings()
        acceptedButtons: Qt.LeftButton | Qt.RightButton
      }

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.discardWidgetSettings()
          event.accepted = true
        }
      }

      Rectangle {
        anchors.centerIn: parent
        width: Math.min(Style.space(420), parent.width - Style.gapsOut * 2)
        height: Math.min(parent.height - Style.space(60), Style.space(380))
        color: root.background
        radius: Style.cornerRadius
        border.color: Style.normalBorderFor(root.foreground, root.accent)
        border.width: Style.normalBorderWidth

        MouseArea { anchors.fill: parent }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.spacing.panelPadding
          spacing: Style.spacing.rowPaddingX

          Text {
            text: root.widgetName(root.widgetDialogEntry.id || "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            text: root.widgetDescription(root.widgetDialogEntry.id || "")
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }

          Flickable {
            id: widgetDialogScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: widgetDialogFormLoader.item ? widgetDialogFormLoader.item.implicitHeight : 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Loader {
              id: widgetDialogFormLoader
              width: widgetDialogScroll.width
              sourceComponent: root.widgetDialogVisible ? formComponent(root.widgetDialogEntry.id || "") : null
              onLoaded: {
                if (item && "entry" in item) item.entry = root.widgetDialogEntry
                if (item && "fieldChanged" in item) {
                  item.fieldChanged.connect(function(key, value) { root.widgetDialogFieldChanged(key, value) })
                }
              }
            }
          }

          Row {
            Layout.alignment: Qt.AlignRight
            spacing: Style.spacing.rowGap
            Button {
              text: "Cancel"
              foreground: root.foreground
              fontFamily: root.fontFamily
              focusable: true
              onClicked: root.discardWidgetSettings()
            }
            Button {
              text: "Apply"
              foreground: root.foreground
              fontFamily: root.fontFamily
              focusable: true
              bordered: true
              onClicked: root.commitWidgetSettings()
            }
          }
        }
      }
    }
  }

  // ===================== bar category ======================================
  component BarCategory: ColumnLayout {
    spacing: Style.spacing.panelGap

    Text {
      text: "Bar"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.iconLarge
      font.bold: true
    }

    Text {
      text: "Drag widgets between the bar's three sections, drop in plugin widgets, and tweak per-widget options. Auto-saves to shell.json."
      color: Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    Row {
      Layout.fillWidth: true
      spacing: Style.spacing.panelGap

      Column {
        spacing: Style.spacing.labelGap

        Text {
          text: "Position"
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        ButtonGroup {
          options: ["top", "right", "bottom", "left"]
          value: root.draft.bar.position
          foreground: root.foreground
          background: root.background
          accent: root.accent
          fontFamily: root.fontFamily
          onChanged: function(v) {
            if (root.draft.bar.position === v) return
            var next = Util.cloneJson(root.draft)
            next.bar.position = v
            root.draft = next
            root.markDirty()
          }
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
          var next = Util.cloneJson(root.draft)
          next.bar.centerAnchor = v === "(none)" ? "" : v
          root.draft = next
          root.markDirty()
        }
      }
    }

    Toggle {
      Layout.fillWidth: true
      label: "Transparent bar"
      description: "Hide the bar background so the wallpaper shows through."
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      checked: root.draft.bar.transparent === true
      onClicked: {
        var next = Util.cloneJson(root.draft)
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
      Layout.preferredHeight: Style.spacing.hairline
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
    }

    Row {
      Layout.alignment: Qt.AlignRight
      Button {
        text: "Reset bar to defaults"
        foreground: root.urgent
        fontFamily: root.fontFamily
        focusable: true
        bordered: true
        onClicked: root.resetBarToDefaults()
      }
    }
  }

  // ===================== bar layout pieces =================================
  component SectionEditor: Column {
    id: section

    property string sectionKey: ""
    property string sectionLabel: ""
    property var entries: root.sectionArray(section.sectionKey)
    Layout.fillWidth: true
    Layout.topMargin: Style.spacing.rowGap
    spacing: Style.spacing.rowGap

    Connections {
      target: root
      function onDraftRevisionChanged() { section.entries = root.sectionArray(section.sectionKey) }
    }

    RowLayout {
      width: section.width
      spacing: Style.spacing.rowGap

      Text {
        text: section.sectionLabel
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        text: "·  " + section.entries.length + (section.entries.length === 1 ? " widget" : " widgets")
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.alignment: Qt.AlignVCenter
      }

      Item { Layout.fillWidth: true; implicitHeight: 1 }

      SearchableDropdown {
        id: addPill
        showLabel: false
        triggerLabel: "󰐕 Add widget"
        value: ""
        placeholderText: "Search widgets..."
        emptyText: "No widgets to add"
        Layout.preferredWidth: Style.spacing.searchableDropdownWidth
        Layout.alignment: Qt.AlignVCenter
        options: {
          var list = root.availableToAdd(section.sectionKey)
          var out = []
          for (var i = 0; i < list.length; i++) {
            out.push({
              value: list[i].id,
              label: list[i].name + (list[i].elsewhere ? "  (elsewhere)" : ""),
              description: list[i].description || ""
            })
          }
          return out
        }
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onChanged: function(v) {
          if (!v) return
          root.addEntry(section.sectionKey, v)
          addPill.value = ""
        }
      }
    }

    Column {
      Layout.fillWidth: true
      width: section.width
      spacing: Style.spacing.labelGap

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
        height: Math.max(Style.space(32), Style.font.bodySmall + Style.spacing.controlPaddingY * 2)
        radius: root.cornerRadius
        color: Style.normalFillFor(root.foreground, root.accent)
        border.color: Style.normalBorderFor(root.foreground, root.accent)
        border.width: Style.normalBorderWidth

        Text {
          anchors.centerIn: parent
          text: "Empty — add a widget"
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
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

    implicitHeight: Style.space(50)
    radius: root.cornerRadius
    color: cardArea.containsMouse || actionRow.activeFocus
      ? Style.hoverFillFor(root.foreground, root.accent)
      : Style.normalFillFor(root.foreground, root.accent)
    border.color: cardArea.containsMouse || actionRow.activeFocus
      ? Style.hoverBorderFor(root.foreground, root.accent)
      : Style.normalBorderFor(root.foreground, root.accent)
    border.width: cardArea.containsMouse || actionRow.activeFocus ? Style.hoverBorderWidth : Style.normalBorderWidth

    Behavior on color { ColorAnimation { duration: 100 } }

    function maybeRestoreActionFocus() {
      if (root.pendingActionFocusSection !== card.sectionKey) return
      if (root.pendingActionFocusIndex !== card.entryIndex) return

      actionRow.actionIndex = root.pendingActionFocusAction
      actionRow.clampActionIndex()
      root.clearPendingActionFocus()

      Qt.callLater(function() {
        actionRow.forceActiveFocus()
        root.ensureBodyItemVisible(card)
      })
    }

    onEntryIndexChanged: maybeRestoreActionFocus()
    Component.onCompleted: maybeRestoreActionFocus()

    Connections {
      target: root
      function onPendingActionFocusRevisionChanged() { card.maybeRestoreActionFocus() }
    }

    Row {
      id: actionRow
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.controlGap
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.labelGap
      activeFocusOnTab: true

      property int actionIndex: 0

      onActiveFocusChanged: if (activeFocus) {
        clampActionIndex()
        root.ensureBodyItemVisible(card)
      }

      function actionVisible(index) {
        switch (index) {
        case 0: return moveUpButton.visible && moveUpButton.enabled
        case 1: return moveDownButton.visible && moveDownButton.enabled
        case 2: return settingsButton.visible && settingsButton.enabled
        case 3: return removeButton.visible && removeButton.enabled
        }
        return false
      }

      function firstActionIndex() {
        for (var i = 0; i < 4; i++) if (actionVisible(i)) return i
        return 0
      }

      function clampActionIndex() {
        if (actionVisible(actionIndex)) return
        actionIndex = firstActionIndex()
      }

      function moveAction(delta) {
        clampActionIndex()
        var next = actionIndex
        while (true) {
          next += delta
          if (next < 0 || next > 3) return
          if (actionVisible(next)) { actionIndex = next; return }
        }
      }

      function activateAction() {
        clampActionIndex()
        switch (actionIndex) {
        case 0: root.moveEntry(card.sectionKey, card.entryIndex, card.entryIndex - 1, actionIndex); return
        case 1: root.moveEntry(card.sectionKey, card.entryIndex, card.entryIndex + 1, actionIndex); return
        case 2: root.openWidgetSettings(card.sectionKey, card.entryIndex, card.entry); return
        case 3: root.removeEntry(card.sectionKey, card.entryIndex); return
        }
      }

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Left || event.text === "h") {
          moveAction(-1); event.accepted = true; return
        }
        if (event.key === Qt.Key_Right || event.text === "l") {
          moveAction(1); event.accepted = true; return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
          activateAction(); event.accepted = true; return
        }
      }

      PanelActionButton {
        id: moveUpButton
        iconText: "󰁝"
        tooltipText: "Move up"
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.subtitle
        size: Style.space(26)
        hasCursor: actionRow.activeFocus && actionRow.actionIndex === 0
        bordered: hasCursor
        onHovered: function(h) { if (h) actionRow.actionIndex = 0 }
        onClicked: root.moveEntry(card.sectionKey, card.entryIndex, card.entryIndex - 1, 0)
      }
      PanelActionButton {
        id: moveDownButton
        iconText: "󰁅"
        tooltipText: "Move down"
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.subtitle
        size: Style.space(26)
        hasCursor: actionRow.activeFocus && actionRow.actionIndex === 1
        bordered: hasCursor
        onHovered: function(h) { if (h) actionRow.actionIndex = 1 }
        onClicked: root.moveEntry(card.sectionKey, card.entryIndex, card.entryIndex + 1, 1)
      }
      PanelActionButton {
        id: settingsButton
        iconText: "󰒓"
        tooltipText: "Settings"
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.subtitle
        size: Style.space(26)
        visible: card.hasSettings
        hasCursor: actionRow.activeFocus && actionRow.actionIndex === 2
        bordered: hasCursor
        onVisibleChanged: if (!visible && actionRow.actionIndex === 2) actionRow.clampActionIndex()
        onHovered: function(h) { if (h) actionRow.actionIndex = 2 }
        onClicked: root.openWidgetSettings(card.sectionKey, card.entryIndex, card.entry)
      }
      PanelActionButton {
        id: removeButton
        iconText: "󰅖"
        tooltipText: "Remove"
        foreground: root.urgent
        hoverColor: root.urgent
        fontFamily: root.fontFamily
        fontSize: Style.font.subtitle
        size: Style.space(26)
        hasCursor: actionRow.activeFocus && actionRow.actionIndex === 3
        bordered: hasCursor
        onHovered: function(h) { if (h) actionRow.actionIndex = 3 }
        onClicked: root.removeEntry(card.sectionKey, card.entryIndex)
      }
    }

    Column {
      anchors.left: parent.left
      anchors.right: actionRow.left
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.rowPaddingX
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xxs

      Text {
        text: card.displayName
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }
      Text {
        visible: text !== ""
        text: card.description
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
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
  }

  // ---------------- per-widget form resolution -----------------------------
  function formComponent(id) {
    var meta = widgetMetadata(id)
    if (meta && meta.settingsForm) {
      switch (meta.settingsForm) {
      case "spacerSettings": return spacerSettingsComponent
      case "clockSettings": return clockSettingsComponent
      case "weatherSettings": return weatherSettingsComponent
      }
    }
    if (widgetSchema(id).length > 0) return dynamicSettingsComponent
    return null
  }

  Component {
    id: dynamicSettingsComponent
    Cmp.DynamicSettingsForm {
      schema: root.widgetSchema(entry.id || "")
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
  }

  Component {
    id: spacerSettingsComponent

    Column {
      id: spacerForm
      signal fieldChanged(string key, var value)
      property var entry: ({})

      spacing: Style.spacing.rowGap
      width: parent ? parent.width : 0

      NumberField {
        label: "Size (pixels)"
        from: 0
        to: 256
        value: spacerForm.entry.size !== undefined ? spacerForm.entry.size : 12
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onModified: function(v) { spacerForm.fieldChanged("size", v) }
      }
    }
  }

  Component {
    id: clockSettingsComponent

    Column {
      id: clockForm
      signal fieldChanged(string key, var value)
      property var entry: ({})

      spacing: Style.spacing.rowGap
      width: parent ? parent.width : 0

      component ClockField: TextField {
        property string fieldKey: ""
        width: parent.width
        foreground: root.foreground
        accent: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        onEditingFinished: if (fieldKey) clockForm.fieldChanged(fieldKey, text)
      }

      Text {
        text: "Horizontal format"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      ClockField {
        fieldKey: "format"
        text: clockForm.entry.format || "dddd HH:mm"
      }

      Text {
        text: "Alternate format (click to toggle)"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      ClockField {
        fieldKey: "formatAlt"
        text: clockForm.entry.formatAlt || "dd MMMM 'W'ww yyyy"
      }

      Text {
        text: "Vertical format (left/right bars)"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      ClockField {
        fieldKey: "verticalFormat"
        text: clockForm.entry.verticalFormat || "HH\n—\nmm"
      }
    }
  }

  Component {
    id: weatherSettingsComponent

    Column {
      id: weatherForm
      signal fieldChanged(string key, var value)
      property var entry: ({})

      spacing: Style.spacing.rowGap
      width: parent ? parent.width : 0

      NumberField {
        label: "Auto-refresh interval (minutes)"
        from: 1
        to: 1440
        value: weatherForm.entry.refreshMinutes !== undefined ? weatherForm.entry.refreshMinutes : 15
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onModified: function(v) { weatherForm.fieldChanged("refreshMinutes", v) }
      }
    }
  }


}
