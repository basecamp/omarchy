import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: root

  // The omarchy-shell host injects omarchyPath from OMARCHY_PATH.
  required property string omarchyPath
  // Injected by the host shell. Shared with the bar settings panel so both
  // see the same widget catalogue.
  required property var barWidgetRegistry
  // Injected by the host shell every time shell.json is reloaded. Holds the
  // `bar:` subtree: position, centerAnchor, layout. The host owns file IO;
  // the bar just renders whatever it's handed. The bar font follows the
  // OS-level fontconfig monospace binding — it is not stored in shell.json.
  required property var barConfig
  // Injected by the host shell. Used for shell-wide actions such as opening
  // settings and persisting inline widget state.
  property var shell: null
  // Mirrors the on-disk `bar-off` flag so the user can hide the bar without
  // killing the entire shell. Wired to BarPanel.visible below; updated by the
  // FileView watcher further down.
  property bool barHidden: false
  property string home: Quickshell.env("HOME")
  property string omarchyConfigDir: home + "/.config/omarchy"
  property var fallbackBarConfig: ({
    position: "top",
    transparent: false,
    centerAnchor: "calendar",
    layout: { left: [], center: [], right: [] }
  })
  property var layoutConfig: fallbackBarConfig.layout
  property string centerAnchor: ""
  property bool transparent: false
  property int barConfigSerial: 0
  property string position: "top"
  // Resolves through fontconfig at paint time (Style.font.family defaults
  // to "monospace"), so changing the system font (via `omarchy-font-set`)
  // updates the bar without a reload.
  property string fontFamily: Style.font.family
  // Bound to the central Color singleton so the bar tracks shell.toml's
  // [bar] section. Property names kept for the rest of this file's bindings.
  property color foreground: Color.bar.text
  property color background: Color.bar.background
  property color urgent: Color.bar.active

  Behavior on foreground { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on background { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on urgent { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  property bool updateAvailable: false
  property bool clockAlt: false
  property var tooltipTarget: null
  property var pendingTooltipTarget: null
  property string tooltipText: ""
  property string pendingTooltipText: ""
  property bool tooltipShown: false
  property int tooltipRequest: 0
  property var activePopout: null
  property var clickTargets: []
  property bool indicatorAreaHovered: false
  property bool indicatorItemHovered: false
  readonly property bool revealInactiveIndicators: indicatorAreaHovered || indicatorItemHovered

  function setIndicatorAreaHovered(hovered) {
    indicatorAreaHovered = hovered
    if (hovered) indicatorHideTimer.stop()
    else indicatorHideTimer.restart()
  }

  function setIndicatorItemHovered(hovered) {
    if (hovered) {
      indicatorItemHovered = true
      indicatorHideTimer.stop()
    } else {
      indicatorHideTimer.restart()
    }
  }

  function registerClickTarget(target) {
    if (!target || clickTargets.indexOf(target) !== -1) return
    var next = clickTargets.slice()
    next.push(target)
    clickTargets = next
  }

  function unregisterClickTarget(target) {
    var next = clickTargets.filter(function(item) { return item !== target })
    clickTargets = next
  }

  function targetWindow(target) {
    return target && target.QsWindow ? target.QsWindow.window : null
  }

  function targetBelongsToWindow(target, window) {
    return !!target && !!window && targetWindow(target) === window
  }

  function targetTooltipHovered(target) {
    return !!target && target.visible !== false && target.opacity !== 0 && target.tooltipHovered === true
  }

  function clearTooltip() {
    tooltipTimer.stop()
    pendingTooltipTarget = null
    pendingTooltipText = ""
    tooltipTarget = null
    tooltipText = ""
    tooltipShown = false
  }

  function requestPopout(owner) {
    if (activePopout === owner) return
    if (activePopout && "close" in activePopout) activePopout.close()
    activePopout = owner
  }

  function releasePopout(owner) {
    if (activePopout === owner) activePopout = null
  }

  readonly property bool vertical: position === "left" || position === "right"
  readonly property int barSize: vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

  signal indicatorsRefreshRequested()

  function normalizePosition(value) {
    var next = String(value || "").trim()
    return /^(top|bottom|left|right)$/.test(next) ? next : "top"
  }

  // Apply tray-pinning on top of the shared layout normalization so the
  // bar host and the bar settings panel can't drift on entry shape.
  function normalizeLayout(layout) {
    var normalized = Util.normalizeLayout(Util.isPlainObject(layout) ? layout : fallbackBarConfig.layout)
    return {
      left:   pinTrayToInner(normalized.left,   "left"),
      center: pinTrayToInner(normalized.center, "center"),
      right:  pinTrayToInner(normalized.right,  "right")
    }
  }

  function indicatorEntriesFromSettings(settings) {
    var source = []
    if (settings.items && typeof settings.items.length === "number") source = settings.items
    else if (settings.indicators && typeof settings.indicators.length === "number") source = settings.indicators

    var result = []
    for (var i = 0; i < source.length; i++) {
      var item = source[i]
      if (typeof item !== "string" && item !== null && typeof item === "object") {
        try {
          item = JSON.parse(JSON.stringify(item))
        } catch (error) {
        }
      }
      var id = entryId(item)
      if (id !== "") result.push(item)
    }
    return result
  }

  // The tray drawer reveals inward (away from the bar edge). Place it at the
  // section's inner edge: start of the right section, end of the left/center
  // sections. The drawer's reserved space then sits next to the bar center,
  // not stranded mid-section.
  function pinTrayToInner(entries, section) {
    var trayEntry = null
    var result = []
    for (var i = 0; i < entries.length; i++) {
      if (entryId(entries[i]) === "tray") trayEntry = entries[i]
      else result.push(entries[i])
    }
    if (trayEntry) {
      if (section === "right") result.unshift(trayEntry)
      else result.push(trayEntry)
    }
    return result
  }

  function applyBarConfig() {
    var config = Util.isPlainObject(barConfig) ? barConfig : fallbackBarConfig

    position = normalizePosition(config.position)
    transparent = config.transparent === true
    centerAnchor = String(config.centerAnchor || "")
    layoutConfig = normalizeLayout(config.layout)
    barConfigSerial++
  }

  onBarConfigChanged: applyBarConfig()

  function layoutEntries(region) {
    var serial = barConfigSerial
    var entries = layoutConfig ? layoutConfig[region] : null
    return Array.isArray(entries) ? entries : []
  }

  function entrySettings(entry) {
    if (!Util.isPlainObject(entry)) return {}
    var copy = {}
    for (var key in entry) {
      if (key === "id") continue
      copy[key] = entry[key]
    }
    return copy
  }

  function entryId(entry) {
    if (typeof entry === "string") return entry
    if (Util.isPlainObject(entry)) {
      var id = entry["id"]
      if (id !== undefined && id !== null && String(id) !== "") return String(id)
    }
    return ""
  }

  function moduleString(entry, key, fallback) {
    var settings = entrySettings(entry)
    var value = settings[key]
    return value === undefined || value === null ? fallback : String(value)
  }

  function entryIndex(entries, name) {
    if (!Array.isArray(entries)) return -1

    for (var i = 0; i < entries.length; i++) {
      if (entryId(entries[i]) === name)
        return i
    }

    return -1
  }

  function entriesBefore(entries, name) {
    var index = entryIndex(entries, name)
    return index <= 0 ? [] : entries.slice(0, index)
  }

  function entriesAfter(entries, name) {
    var index = entryIndex(entries, name)
    return index === -1 ? [] : entries.slice(index + 1)
  }

  function canonicalWidgetId(name) {
    switch (String(name)) {
    case "weatherFlyout": return "weather"
    default: return String(name)
    }
  }

  function builtinModuleComponent(name) {
    switch (String(name)) {
    case "omarchy": return omarchyModuleComponent
    case "workspaces": return workspacesModuleComponent
    case "clock": return clockModuleComponent
    case "update": return updateModuleComponent
    case "indicators": return indicatorsModuleComponent
    case "tray": return trayModuleComponent
    default: return null
    }
  }

  function expandPath(path) {
    var value = String(path || "")
    if (value === "") return ""
    if (value.indexOf("~/") === 0) return home + value.substring(1)
    if (value.indexOf("$HOME/") === 0) return home + value.substring(5)
    return value
  }

  function customModuleSafeName(name) {
    var value = String(name || "")
    return value !== "" && value.indexOf("..") === -1 && value[0] !== "/"
  }

  function customModuleType(entry) {
    var settings = entrySettings(entry)
    var type = String(settings.type || "")
    if (type) return type
    if (settings.exec) return "command"
    if (settings.source) return "qml"
    return ""
  }

  function customModuleSource(entry) {
    var settings = entrySettings(entry)
    var name = entryId(entry)
    var source = settings.source ? expandPath(settings.source) : ""
    if (!source && customModuleSafeName(name))
      source = omarchyConfigDir + "/bar/modules/" + String(name) + ".qml"

    return source ? Util.fileUrl(source) : ""
  }

  // First-party modules are registered with the BarWidgetRegistry at startup.
  // Each entry maps a module id to its display metadata; the QML source is
  // loaded asynchronously via Qt.createComponent.
  readonly property var firstPartyWidgetMetadata: ({
    "media":              { displayName: "Media",              description: "MPRIS now-playing with playback controls",   category: "Media",    allowMultiple: false },
    "audioPanel":         { displayName: "Audio",              description: "Volume slider, output picker, per-app mixer", category: "Audio",    allowMultiple: false, sourceDir: "../panels", sourceName: "Audio" },
    "monitorPanel":       { displayName: "Display",            description: "Brightness slider and laptop display controls", category: "System",   allowMultiple: false, sourceDir: "../panels", sourceName: "Monitor" },
    "networkPanel":       { displayName: "Network",            description: "Wi-Fi list and connection state",            category: "Network",  allowMultiple: false, sourceDir: "../panels", sourceName: "Network" },
    "powerPanel":         { displayName: "Power",              description: "Battery, power profile, and system stats",    category: "System",   allowMultiple: false, sourceDir: "../panels", sourceName: "Power" },
    "bluetoothPanel":     { displayName: "Bluetooth",          description: "Bluetooth device list with connect/disconnect", category: "Network", allowMultiple: false, sourceDir: "../panels", sourceName: "Bluetooth" },
    "calendar":           { displayName: "Calendar",           description: "Clock with month-grid popup",                  category: "Time",     allowMultiple: false, settingsForm: "calendarSettings" },
    "notificationCenter": { displayName: "Notification center", description: "Recent notifications + DND",  category: "Status",   allowMultiple: false },
    "systemStats":        { displayName: "System stats",       description: "CPU icon — hover for graphs, click to open btop", category: "System",   allowMultiple: false },
    "weather":            { displayName: "Weather",            description: "Weather pill with detail popup",              category: "Info",     allowMultiple: false, settingsForm: "weatherSettings" },
    "idleInhibitor":      { displayName: "Stay awake",         description: "Toggle whether the system can idle",          category: "System",   allowMultiple: false },
    "microphone":         { displayName: "Microphone",         description: "Mic input state and mute toggle",             category: "Audio",    allowMultiple: false },
    "activeWindow":       { displayName: "Active window",      description: "Title of the focused window",                 category: "Compositor", allowMultiple: false },
    "keyboardLayout":     { displayName: "Keyboard layout",    description: "Current xkb layout, click cycles",            category: "Compositor", allowMultiple: false },
    "lockKeys":           { displayName: "Lock keys",          description: "Caps / Num / Scroll lock indicators",          category: "System",   allowMultiple: false },
    "spacer":             { displayName: "Spacer",             description: "Configurable blank space",                    category: "Layout",   allowMultiple: true,  settingsForm: "spacerSettings" }
  })

  property var registeredFirstPartyComponents: ({})

  Component.onCompleted: {
    registerFirstPartyWidgets()
    applyBarConfig()
  }

  function registerFirstPartyWidgets() {
    var ids = Object.keys(firstPartyWidgetMetadata)
    for (var i = 0; i < ids.length; i++) {
      var id = ids[i]
      if (barWidgetRegistry.has(id)) continue
      registerOneFirstPartyWidget(id)
    }
  }

  function registerOneFirstPartyWidget(id) {
    var meta = firstPartyWidgetMetadata[id] || {}
    var sourceDir = meta.sourceDir || "widgets"
    var sourceName = meta.sourceName || id
    var url = Qt.resolvedUrl(sourceDir + "/" + sourceName + ".qml")
    var enrichedMeta = {
      displayName: meta.displayName || id,
      description: meta.description || "",
      category: meta.category || "Misc",
      allowMultiple: meta.allowMultiple === true,
      settingsForm: meta.settingsForm || "",
      source: "first-party"
    }
    var comp = Qt.createComponent(url, Component.Asynchronous)
    function finalize() {
      if (comp.status === Component.Ready) {
        barWidgetRegistry.register(id, comp, enrichedMeta)
        var next = ({})
        for (var k in registeredFirstPartyComponents) next[k] = registeredFirstPartyComponents[k]
        next[id] = comp
        registeredFirstPartyComponents = next
      } else if (comp.status === Component.Error) {
        console.warn("first-party widget " + id + " failed to load: " + comp.errorString())
      }
    }
    if (comp.status === Component.Loading) comp.statusChanged.connect(finalize)
    else finalize()
  }

  function run(command) {
    if (!command) return

    launcher.command = ["bash", "-lc", command]
    launcher.startDetached()
  }

  function openBarSettings() {
    if (root.shell && typeof root.shell.summon === "function") {
      root.shell.summon("omarchy.settings", "{}")
    } else {
      root.run("omarchy-launch-bar-settings")
    }
  }

  function toggleTransparency() {
    var nextTransparent = !(root.transparent === true)
    if (root.shell && typeof root.shell.mutateShellConfig === "function") {
      root.shell.mutateShellConfig(function(config) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        config.bar.transparent = nextTransparent
      })
    } else {
      root.transparent = nextTransparent
    }
  }

  function runProcess(process) {
    if (!process.running)
      process.running = true
  }

  function showTooltip(target, text) {
    clearTooltip()

    if (!targetTooltipHovered(target) || !text) {
      tooltipRequest += 1
      return
    }

    var request = tooltipRequest + 1
    tooltipRequest = request
    pendingTooltipTarget = target
    pendingTooltipText = text

    Qt.callLater(function() {
      if (request !== tooltipRequest) return
      if (!targetTooltipHovered(pendingTooltipTarget)) {
        clearTooltip()
        return
      }
      tooltipTarget = pendingTooltipTarget
      tooltipText = pendingTooltipText
      pendingTooltipTarget = null
      pendingTooltipText = ""
      tooltipTimer.restart()
    })
  }

  function hideTooltip(target) {
    if (tooltipTarget !== target && pendingTooltipTarget !== target) return

    tooltipRequest += 1
    clearTooltip()
  }

  function refreshUpdate() {
    runProcess(updateProc)
  }

  function refreshIndicators() {
    indicatorsRefreshRequested()
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id)
        return values[i]
    }

    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1)
        ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function trayIconSource(icon) {
    var value = String(icon || "")
    var marker = "?path="
    var markerIndex = value.indexOf(marker)
    if (markerIndex === -1) return value

    var name = value.substring(0, markerIndex).split("/").pop()
    var iconPath = value.substring(markerIndex + marker.length).split("&")[0]
    return Util.fileUrl(iconPath + "/hicolor/16x16/status/" + name + ".png")
  }

  function trayTooltip(item) {
    return item.tooltipTitle || item.title || item.id || ""
  }

  function focusWorkspace(id) {
    root.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  function clockEntry() {
    var serial = barConfigSerial
    var sections = ["left", "center", "right"]
    for (var i = 0; i < sections.length; i++) {
      var entries = layoutEntries(sections[i])
      var idx = entryIndex(entries, "clock")
      if (idx !== -1) return entries[idx]
    }
    return null
  }

  function clockText() {
    var entry = clockEntry()
    if (clockAlt)
      return Qt.formatDateTime(systemClock.date, moduleString(entry, "formatAlt", "dd MMMM 'W'ww yyyy"))

    if (vertical)
      return Qt.formatDateTime(systemClock.date, moduleString(entry, "verticalFormat", "HH\n—\nmm"))

    return Qt.formatDateTime(systemClock.date, moduleString(entry, "format", "dddd HH:mm"))
  }

  SystemClock {
    id: systemClock
    precision: SystemClock.Minutes
  }

  Process { id: launcher }

  Timer {
    id: tooltipTimer
    interval: 400
    onTriggered: {
      if (root.targetTooltipHovered(root.tooltipTarget)) root.tooltipShown = true
      else root.clearTooltip()
    }
  }

  Timer {
    interval: 100
    running: root.tooltipShown
    repeat: true
    onTriggered: if (!root.targetTooltipHovered(root.tooltipTarget)) root.hideTooltip(root.tooltipTarget)
  }

  Timer {
    id: indicatorHideTimer
    interval: 120
    onTriggered: {
      if (!root.indicatorAreaHovered)
        root.indicatorItemHovered = false
    }
  }

  // Presence of the `bar-off` flag = bar hidden. Watching the parent toggles
  // directory because FileView can't observe a file that doesn't exist yet,
  // and the flag is created/removed by `omarchy-toggle-bar`.
  Process {
    id: barHiddenProbe
    running: true
    command: ["bash", "-lc", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser { onRead: function(line) { root.barHidden = String(line).trim() === "yes" } }
  }
  FileView {
    path: root.home + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: barHiddenProbe.running = true
  }

  Process {
    id: updateProc
    command: ["bash", "-lc", "omarchy-update-available"]
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.updateAvailable = exitCode === 0
    }
  }

  Timer {
    interval: 21600000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshUpdate()
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshIndicators()
  }

  IpcHandler {
    target: "bar"

    function refreshUpdate(): void {
      root.refreshUpdate()
    }

    function refreshScreenRecording(): void {
      root.refreshIndicators()
    }

    function refreshIndicators(): void {
      root.refreshIndicators()
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarPanel {
        required property var modelData

        screen: modelData
      }
    }
  }

  component BarPanel: PanelWindow {
    id: barWindow

    visible: !root.barHidden

    anchors {
      top: root.position === "top" || root.vertical
      bottom: root.position === "bottom" || root.vertical
      left: root.position === "left" || !root.vertical
      right: root.position === "right" || !root.vertical
    }

    implicitWidth: root.vertical ? root.barSize : 0
    implicitHeight: root.vertical ? 0 : root.barSize
    color: root.transparent ? "transparent" : root.background
    WlrLayershell.namespace: "omarchy-bar"
    WlrLayershell.layer: WlrLayer.Top

    Loader {
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalBar : horizontalBar
    }

    PopupWindow {
      id: tooltipWindow

      visible: root.tooltipShown && root.tooltipTarget !== null && root.tooltipText !== "" && root.targetBelongsToWindow(root.tooltipTarget, barWindow)
      color: "transparent"
      implicitWidth: Math.ceil(tooltipBubble.implicitWidth)
      implicitHeight: Math.ceil(tooltipBubble.implicitHeight)

      anchor {
        id: tooltipAnchor
        window: barWindow
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1

        onAnchoring: {
          var target = root.tooltipTarget
          if (!root.targetBelongsToWindow(target, barWindow)) return

          var popupWidth = tooltipWindow.implicitWidth
          var popupHeight = tooltipWindow.implicitHeight
          var localX = target.width / 2 - popupWidth / 2
          var localY = target.height + 6

          if (root.position === "bottom") {
            localY = -popupHeight - 6
          } else if (root.position === "left") {
            localX = target.width + 6
            localY = target.height / 2 - popupHeight / 2
          } else if (root.position === "right") {
            localX = -popupWidth - 6
            localY = target.height / 2 - popupHeight / 2
          }

          var point = barWindow.contentItem.mapFromItem(target, localX, localY)
          tooltipAnchor.rect.x = Math.round(point.x)
          tooltipAnchor.rect.y = Math.round(point.y)
        }
      }

      Rectangle {
        id: tooltipBubble
        implicitWidth: tooltipLabel.implicitWidth + 20
        implicitHeight: tooltipLabel.implicitHeight + 14
        color: Color.tooltip.background
        border.color: Color.tooltip.border
        border.width: 1
        radius: Style.cornerRadius

        Text {
          id: tooltipLabel
          anchors.centerIn: parent
          text: root.tooltipText
          color: Color.tooltip.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }
    }

    Component {
      id: horizontalBar

      Item {
        anchors.fill: parent

        CenterModules { anchors.fill: parent }

        LeftModules {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
        }

        RightModules {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }

    Component {
      id: verticalBar

      Item {
        anchors.fill: parent

        CenterModules { anchors.fill: parent }

        LeftModules {
          anchors.top: parent.top
          anchors.topMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
        }

        RightModules {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }
    }
  }

  Component { id: emptyModuleComponent; Item { implicitWidth: 0; implicitHeight: 0; visible: false } }
  Component { id: omarchyModuleComponent; OmarchyModule {} }
  Component { id: workspacesModuleComponent; WorkspacesModule {} }
  Component { id: clockModuleComponent; ClockModule {} }
  Component { id: updateModuleComponent; UpdateModule {} }
  Component { id: indicatorsModuleComponent; IndicatorsModule {} }
  Component { id: trayModuleComponent; TrayModule {} }

  function findCenterAnchorEntry() {
    var entries = root.layoutEntries("center")
    var idx = root.entryIndex(entries, root.centerAnchor)
    return idx === -1 ? null : entries[idx]
  }

  component LeftModules: ModuleList {
    entries: root.layoutEntries("left")
  }

  component RightModules: ModuleList {
    entries: root.layoutEntries("right")
  }

  component CenterModules: Item {
    id: centerRoot

    property var entries: root.layoutEntries("center")
    readonly property bool hasAnchor: root.entryIndex(entries, root.centerAnchor) !== -1
    readonly property var anchorEntry: root.findCenterAnchorEntry()

    Loader {
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalCenterModules : horizontalCenterModules
    }

    Component {
      id: horizontalCenterModules

      Item {
        anchors.fill: parent

        CenterGestureArea { anchors.fill: parent }

        ModuleList {
          visible: !centerRoot.hasAnchor
          entries: centerRoot.entries
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
          anchors.right: centerAnchorModule.left
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          entry: centerRoot.anchorEntry
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
          anchors.left: centerAnchorModule.right
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }
      }
    }

    Component {
      id: verticalCenterModules

      Item {
        anchors.fill: parent

        CenterGestureArea { anchors.fill: parent }

        ModuleList {
          visible: !centerRoot.hasAnchor
          entries: centerRoot.entries
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
          anchors.bottom: centerAnchorModule.top
          anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          entry: centerRoot.anchorEntry
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
          anchors.top: centerAnchorModule.bottom
          anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        }
      }
    }
  }

  component CenterGestureArea: MouseArea {
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        root.openBarSettings()
        mouse.accepted = true
      }
    }

    onDoubleClicked: function(mouse) {
      if (mouse.button !== Qt.RightButton) {
        root.toggleTransparency()
        mouse.accepted = true
      }
    }
  }

  component ModuleList: Loader {
    id: moduleListRoot

    property var entries: []

    visible: entries.length > 0
    sourceComponent: root.vertical ? verticalModuleList : horizontalModuleList
    width: item ? item.implicitWidth : 0
    height: item ? item.implicitHeight : 0

    Component {
      id: horizontalModuleList

      Row {
        spacing: 0

        Repeater {
          model: moduleListRoot.entries

          ModuleSlot {
            required property var modelData
            entry: modelData
          }
        }
      }
    }

    Component {
      id: verticalModuleList

      Column {
        spacing: 0

        Repeater {
          model: moduleListRoot.entries

          ModuleSlot {
            required property var modelData
            entry: modelData
          }
        }
      }
    }
  }

  component ModuleSlot: Item {
    id: slot

    required property var entry
    readonly property string moduleName: root.entryId(entry)
    readonly property var moduleSettings: root.entrySettings(entry)
    readonly property string customType: root.customModuleType(entry)
    readonly property var builtinComponent: customType ? null : root.builtinModuleComponent(moduleName)
    // Re-evaluate when the registry mutates (Component reference changes,
    // plugin enabled/disabled, etc.). Reading the `widgets` property creates
    // the binding dependency — the wrapped function call alone wouldn't.
    readonly property var registryComponent: {
      var w = root.barWidgetRegistry.widgets
      if (customType || builtinComponent) return null
      var registryName = root.canonicalWidgetId(moduleName)
      return w[registryName] ? w[registryName].component : null
    }
    readonly property bool qmlCustom: customType === "qml"
    readonly property bool commandCustom: customType === "command"
    readonly property bool registered: registryComponent !== null
    readonly property var activeItem: {
      if (registered) return registryLoader.item
      if (qmlCustom) return qmlLoader.item
      return componentLoader.item
    }

    implicitWidth: activeItem && activeItem.visible ? (root.vertical ? root.barSize : activeItem.implicitWidth) : 0
    implicitHeight: activeItem && activeItem.visible ? activeItem.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight

    Loader {
      id: componentLoader
      active: !slot.qmlCustom && !slot.registered
      sourceComponent: slot.builtinComponent || (slot.commandCustom ? customCommandModuleComponent : emptyModuleComponent)
      anchors.fill: parent
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: registryLoader
      active: slot.registered
      sourceComponent: slot.registered ? slot.registryComponent : null
      anchors.fill: parent
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: qmlLoader
      active: slot.qmlCustom
      source: slot.qmlCustom ? root.customModuleSource(slot.entry) : ""
      anchors.fill: parent
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    onActiveItemChanged: Qt.callLater(injectProps)
    onModuleSettingsChanged: injectProps()

    function injectProps() {
      var target = activeItem
      if (!target) return
      if ("bar" in target) target.bar = root
      if ("moduleName" in target) target.moduleName = moduleName
      if ("settings" in target) target.settings = moduleSettings
    }

    Component {
      id: customCommandModuleComponent
      CustomCommandModule { entry: slot.entry }
    }
  }

  component CustomCommandModule: ModuleButton {
    id: customRoot

    required property var entry
    readonly property string moduleName: root.entryId(entry)
    readonly property var settings: root.entrySettings(entry)
    property string outputText: ""
    property string outputTooltip: ""
    property bool outputActive: false

    function setting(name, fallback) {
      var value = settings ? settings[name] : undefined
      return value === undefined || value === null ? fallback : value
    }

    function update(raw) {
      var data = root.parseModuleJson(raw)
      var klass = data.class || data.alt || ""

      outputText = data.text || String(raw || "").trim()
      outputTooltip = data.tooltip || String(setting("tooltip", ""))
      outputActive = klass === "active" || (Array.isArray(klass) && klass.indexOf("active") !== -1)
    }

    text: outputText || String(setting("text", ""))
    tooltipText: outputTooltip || String(setting("tooltip", ""))
    active: outputActive
    keepSpace: setting("keepSpace", false) === true
    horizontalMargin: Number(setting("horizontalMargin", 7.5))
    verticalPadding: Number(setting("verticalPadding", 6))
    fontSize: Number(setting("fontSize", 12))

    onPressed: function(button) {
      var command = ""
      if (button === Qt.RightButton)
        command = String(setting("onRightClick", ""))
      else if (button === Qt.MiddleButton)
        command = String(setting("onMiddleClick", ""))
      else
        command = String(setting("onClick", ""))

      if (command) root.run(command)
    }

    Process {
      id: customProc
      command: ["bash", "-lc", String(customRoot.setting("exec", ""))]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: customRoot.update(text)
      }
    }

    Timer {
      interval: Math.max(1, Number(customRoot.setting("interval", 5))) * 1000
      running: String(customRoot.setting("exec", "")) !== ""
      repeat: true
      triggeredOnStart: true
      onTriggered: root.runProcess(customProc)
    }
  }

  component ModuleButton: Item {
    id: buttonRoot

    property string text: ""
    property bool active: false
    property bool keepSpace: false
    property string fontFamily: root.fontFamily
    property real fontSize: Style.font.body
    property real horizontalMargin: 7.5
    property real rightExtraMargin: 0
    property real verticalPadding: 6
    property real textRotation: 0
    property real fixedWidth: -1
    property real fixedHeight: -1
    property string tooltipText: ""
    readonly property bool tooltipHovered: visible && opacity > 0 && mouseArea.containsMouse

    signal pressed(int button)
    signal wheelMoved(int delta)

    function triggerPress(button) {
      root.hideTooltip(buttonRoot)
      buttonRoot.pressed(button)
    }

    Component.onCompleted: root.registerClickTarget(buttonRoot)
    Component.onDestruction: root.unregisterClickTarget(buttonRoot)

    visible: text !== "" || keepSpace
    opacity: text === "" ? 0 : 1
    implicitWidth: fixedWidth > 0 ? fixedWidth : (root.vertical ? root.barSize : Math.max(12, label.implicitWidth + horizontalMargin * 2 + rightExtraMargin))
    implicitHeight: fixedHeight > 0 ? fixedHeight : (root.vertical ? Math.max(12, label.implicitHeight + verticalPadding * 2) : root.barSize)

    Text {
      id: label
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: root.vertical ? 0 : -buttonRoot.rightExtraMargin / 2
      text: buttonRoot.text
      color: buttonRoot.active ? root.urgent : root.foreground
      font.family: buttonRoot.fontFamily
      font.pixelSize: buttonRoot.fontSize
      renderType: Text.NativeRendering
      rotation: buttonRoot.textRotation
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.showTooltip(buttonRoot, buttonRoot.tooltipText)
      onExited: root.hideTooltip(buttonRoot)
      onClicked: function(mouse) { buttonRoot.triggerPress(mouse.button) }
      onWheel: function(wheel) { buttonRoot.wheelMoved(wheel.angleDelta.y) }
    }
  }

  component IndicatorsModule: Item {
    id: indicatorsRoot

    property var bar: root
    property string moduleName: "indicators"
    property var settings: ({})
    readonly property var indicatorEntries: root.indicatorEntriesFromSettings(settings)
    property var activeIndicatorIds: []
    property var indicatorActiveStates: ({})
    readonly property var activeIndicatorEntries: activeEntriesFromOrder(activeIndicatorIds)

    function hasIndicatorId(id) {
      for (var i = 0; i < indicatorEntries.length; i++) {
        if (root.entryId(indicatorEntries[i]) === id) return true
      }
      return false
    }

    function activeEntriesFromOrder(ids) {
      var result = []

      for (var i = 0; i < ids.length; i++) {
        var id = ids[i]
        for (var j = 0; j < indicatorEntries.length; j++) {
          var entry = indicatorEntries[j]
          if (root.entryId(entry) === id) {
            result.push(entry)
            break
          }
        }
      }

      return result
    }

    function copyActiveStates() {
      var states = {}
      for (var id in indicatorActiveStates) {
        if (indicatorActiveStates[id] === true) states[id] = true
      }
      return states
    }

    function orderedActiveIds(states, preferredOrder) {
      var ids = []

      for (var i = 0; i < preferredOrder.length; i++) {
        var id = preferredOrder[i]
        if (ids.indexOf(id) === -1 && hasIndicatorId(id) && states[id] === true) ids.push(id)
      }

      return ids
    }

    function setIndicatorActive(entry, active) {
      var id = root.entryId(entry)
      if (id === "") return

      var states = copyActiveStates()
      if (active) states[id] = true
      else delete states[id]

      indicatorActiveStates = states

      var ids = orderedActiveIds(states, activeIndicatorIds)
      if (active && ids.indexOf(id) === -1 && hasIndicatorId(id)) ids.push(id)
      activeIndicatorIds = ids
    }

    function syncActiveIndicatorOrder() {
      activeIndicatorIds = orderedActiveIds(indicatorActiveStates, activeIndicatorIds)
    }

    onIndicatorEntriesChanged: syncActiveIndicatorOrder()

    implicitWidth: root.vertical ? verticalIndicators.implicitWidth : horizontalIndicators.implicitWidth
    implicitHeight: root.vertical ? verticalIndicators.implicitHeight : horizontalIndicators.implicitHeight

    Row {
      id: horizontalIndicators

      visible: !root.vertical
      spacing: 0

      IndicatorBlock {
        indicatorsModule: indicatorsRoot
        indicatorEntries: indicatorsRoot.activeIndicatorEntries
        indicatorBlock: "active"
        horizontal: true
      }

      Item {
        id: inactiveHorizontalArea

        implicitWidth: inactiveHorizontalBlock.implicitWidth
        implicitHeight: inactiveHorizontalBlock.implicitHeight
        width: implicitWidth
        height: implicitHeight

        IndicatorBlock {
          id: inactiveHorizontalBlock
          anchors.fill: parent
          indicatorsModule: indicatorsRoot
          indicatorEntries: indicatorsRoot.indicatorEntries
          indicatorBlock: "inactive"
          horizontal: true
          reportActiveState: !root.vertical
        }

        HoverHandler {
          onHoveredChanged: root.setIndicatorAreaHovered(hovered)
        }
      }
    }

    Column {
      id: verticalIndicators

      visible: root.vertical
      spacing: 0

      IndicatorBlock {
        indicatorsModule: indicatorsRoot
        indicatorEntries: indicatorsRoot.activeIndicatorEntries
        indicatorBlock: "active"
        horizontal: false
      }

      Item {
        id: inactiveVerticalArea

        implicitWidth: inactiveVerticalBlock.implicitWidth
        implicitHeight: inactiveVerticalBlock.implicitHeight
        width: implicitWidth
        height: implicitHeight

        IndicatorBlock {
          id: inactiveVerticalBlock
          anchors.fill: parent
          indicatorsModule: indicatorsRoot
          indicatorEntries: indicatorsRoot.indicatorEntries
          indicatorBlock: "inactive"
          horizontal: false
          reportActiveState: root.vertical
        }

        HoverHandler {
          onHoveredChanged: root.setIndicatorAreaHovered(hovered)
        }
      }
    }
  }

  component IndicatorBlock: Item {
    id: indicatorBlockRoot

    property var indicatorEntries: []
    property var indicatorsModule: null
    property string indicatorBlock: "active"
    property bool horizontal: true
    property bool reportActiveState: false

    implicitWidth: blockLoader.item ? blockLoader.item.childrenRect.width : 0
    implicitHeight: blockLoader.item ? blockLoader.item.childrenRect.height : 0
    width: implicitWidth
    height: implicitHeight

    Loader {
      id: blockLoader

      anchors.fill: parent
      sourceComponent: indicatorBlockRoot.horizontal ? horizontalIndicatorBlock : verticalIndicatorBlock
    }

    Component {
      id: horizontalIndicatorBlock

      Row {
        spacing: 0

        Repeater {
          model: indicatorBlockRoot.indicatorEntries

          IndicatorLoader {
            required property var modelData
            indicatorsModule: indicatorBlockRoot.indicatorsModule
            entry: modelData
            indicatorBlock: indicatorBlockRoot.indicatorBlock
            reportActiveState: indicatorBlockRoot.reportActiveState
          }
        }
      }
    }

    Component {
      id: verticalIndicatorBlock

      Column {
        spacing: 0

        Repeater {
          model: indicatorBlockRoot.indicatorEntries

          IndicatorLoader {
            required property var modelData
            indicatorsModule: indicatorBlockRoot.indicatorsModule
            entry: modelData
            indicatorBlock: indicatorBlockRoot.indicatorBlock
            reportActiveState: indicatorBlockRoot.reportActiveState
          }
        }
      }
    }
  }

  component IndicatorLoader: Item {
    id: indicatorSlot

    required property var entry
    property var indicatorsModule: null
    required property string indicatorBlock
    property bool reportActiveState: false
    readonly property string indicatorId: root.entryId(entry)
    readonly property var indicatorSettings: root.entrySettings(entry)

    implicitWidth: indicatorSource.item && indicatorSource.item.visible ? indicatorSource.item.implicitWidth : 0
    implicitHeight: indicatorSource.item && indicatorSource.item.visible ? indicatorSource.item.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight
    onEntryChanged: {
      injectProps()
      syncActiveState()
    }
    onIndicatorBlockChanged: injectProps()
    onIndicatorSettingsChanged: injectProps()
    onIndicatorsModuleChanged: syncActiveState()
    onReportActiveStateChanged: syncActiveState()

    Loader {
      id: indicatorSource

      anchors.fill: parent
      source: indicatorSlot.indicatorId ? Qt.resolvedUrl("indicators/" + indicatorSlot.indicatorId + ".qml") : ""
      onLoaded: {
        indicatorSlot.injectProps()
        indicatorSlot.syncActiveState()
      }
      onStatusChanged: if (status === Loader.Error) console.warn("Indicator loader error", indicatorSlot.indicatorId, source)
    }

    Connections {
      target: indicatorSource.item
      ignoreUnknownSignals: true
      function onActiveChanged() { indicatorSlot.syncActiveState() }
    }

    function injectProps() {
      var target = indicatorSource.item
      if (!target) return
      if ("bar" in target) target.bar = root
      if ("moduleName" in target) target.moduleName = indicatorId
      if ("settings" in target) target.settings = indicatorSettings
      if ("indicatorBlock" in target) target.indicatorBlock = indicatorBlock
    }

    function syncActiveState() {
      if (!reportActiveState || !indicatorsModule || !indicatorsModule.setIndicatorActive) return
      indicatorsModule.setIndicatorActive(entry, !!indicatorSource.item && indicatorSource.item.active === true)
    }
  }

  component OmarchyModule: ModuleButton {
    text: "\ue900"
    fontFamily: "omarchy"
    horizontalMargin: 7.5
    onPressed: function(button) {
      if (button === Qt.RightButton) root.run("xdg-terminal-exec")
      else root.run("omarchy-shell menu toggle root")
    }
  }

  component WorkspacesModule: GridLayout {
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(2)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      ModuleButton {
        required property int modelData

        property var workspace: root.workspaceById(modelData)
        property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        text: focused ? "󱓻" : (modelData === 10 ? "0" : String(modelData))
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : 22
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
      }
    }
  }

  component ClockModule: ModuleButton {
    text: root.clockText()
    horizontalMargin: 8.75
    verticalPadding: 8.75
    onPressed: function(button) {
      if (button === Qt.RightButton) root.run("omarchy-launch-floating-terminal-with-presentation omarchy-tz-select")
      else root.clockAlt = !root.clockAlt
    }
  }

  component UpdateModule: ModuleButton {
    text: root.updateAvailable ? "" : ""
    fontSize: Style.font.caption
    tooltipText: root.updateAvailable ? "Omarchy update available" : ""
    onPressed: function() { root.run("omarchy-launch-floating-terminal-with-presentation omarchy-update") }
  }

  component TrayModule: Item {
    id: trayRoot

    property bool expanded: false
    property bool managePopupOpen: false
    function close() { managePopupOpen = false }

    // Re-resolve the tray's own entry settings whenever the bar layout reloads.
    readonly property var trayEntry: {
      var serial = root.barConfigSerial
      var sections = ["left", "center", "right"]
      for (var s = 0; s < sections.length; s++) {
        var arr = root.layoutEntries(sections[s])
        for (var i = 0; i < arr.length; i++) {
          if (root.entryId(arr[i]) === "tray") return arr[i]
        }
      }
      return ({})
    }
    readonly property var pinnedIds: Array.isArray(trayEntry.pinned) ? trayEntry.pinned : []
    readonly property var hiddenIds: Array.isArray(trayEntry.hidden) ? trayEntry.hidden : []

    function classifyItem(item) {
      var iid = String(item.id || "")
      if (hiddenIds.indexOf(iid) !== -1) return "hidden"
      if (pinnedIds.indexOf(iid) !== -1) return "pinned"
      return "drawer"
    }

    function bucket(category) {
      var values = SystemTray.items.values
      var result = []
      for (var i = 0; i < values.length; i++) {
        var item = values[i]
        if (item.status === Status.Passive) continue
        if (category === "all") { result.push(item); continue }
        if (classifyItem(item) === category) result.push(item)
      }
      return result
    }

    readonly property var pinnedItems: bucket("pinned")
    readonly property var drawerItems: bucket("drawer")
    readonly property var allItems: bucket("all")
    readonly property int drawerCount: drawerItems.length
    readonly property int drawerExtent: drawerCount > 0 ? drawerCount * 16 + (drawerCount - 1) * 17 : 0
    // Match Waybar's group/tray-expander drawer transition-duration.
    readonly property int animationDuration: 600
    property real revealProgress: expanded ? 1 : 0
    readonly property real revealExtent: drawerExtent * revealProgress

    Behavior on revealProgress {
      NumberAnimation { duration: trayRoot.animationDuration; easing.type: Easing.OutCubic }
    }

    function persistTrayState(pinned, hidden) {
      if (!root.shell || typeof root.shell.updateEntryInline !== "function") return
      root.shell.updateEntryInline("tray", { id: "tray", pinned: pinned, hidden: hidden })
    }

    function togglePin(iid) {
      var p = pinnedIds.slice(), h = hiddenIds.slice()
      var idx = p.indexOf(iid)
      if (idx !== -1) p.splice(idx, 1)
      else {
        p.push(iid)
        var hi = h.indexOf(iid); if (hi !== -1) h.splice(hi, 1)
      }
      persistTrayState(p, h)
    }

    function toggleHide(iid) {
      var p = pinnedIds.slice(), h = hiddenIds.slice()
      var idx = h.indexOf(iid)
      if (idx !== -1) h.splice(idx, 1)
      else {
        h.push(iid)
        var pi = p.indexOf(iid); if (pi !== -1) p.splice(pi, 1)
      }
      persistTrayState(p, h)
    }

    visible: pinnedItems.length > 0 || drawerCount > 0
    clip: false
    implicitWidth: root.vertical ? root.barSize : trayContent.implicitWidth
    implicitHeight: root.vertical ? trayContent.implicitHeight : root.barSize

    Loader {
      id: trayContent
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalTray : horizontalTray
    }

    Component {
      id: horizontalTray

      Item {
        id: horizontalTrayRoot

        readonly property int pinnedWidth: pinnedRow.implicitWidth
        readonly property int drawerBlockWidth: trayRoot.allItems.length > 0 ? expandIcon.implicitWidth + trayRoot.drawerExtent : 0

        implicitWidth: pinnedWidth + drawerBlockWidth
        implicitHeight: root.barSize

        // Mask out the empty area the collapsed drawer reserves for its slide-in,
        // so hovering it doesn't trigger expand and clicks pass through.
        containmentMask: QtObject {
          function contains(point: point): bool {
            if (point.y < 0 || point.y > horizontalTrayRoot.height) return false
            // Drawer reveals leftward; chevron sits at the right end when collapsed
            // and slides left as it opens. The visible region starts at the chevron.
            var chevronX = trayRoot.drawerExtent - trayRoot.revealExtent
            if (point.x >= chevronX && point.x <= horizontalTrayRoot.drawerBlockWidth) return true
            // Pinned items, placed to the right of the drawer block.
            var pinnedStart = horizontalTrayRoot.drawerBlockWidth
            return point.x >= pinnedStart && point.x <= horizontalTrayRoot.implicitWidth
          }
        }

        Item {
          id: drawerArea
          x: 0
          width: horizontalTrayRoot.drawerBlockWidth
          height: root.barSize
          visible: trayRoot.allItems.length > 0

          HoverHandler {
            onHoveredChanged: trayRoot.expanded = hovered
          }

          ModuleButton {
            id: expandIcon
            width: implicitWidth
            height: implicitHeight
            x: trayRoot.drawerExtent - trayRoot.revealExtent
            text: ""
            horizontalMargin: 9
            verticalPadding: 6
            onPressed: function(button) {
              if (button === Qt.RightButton) trayRoot.managePopupOpen = !trayRoot.managePopupOpen
            }
          }

          Item {
            id: trayClip
            x: expandIcon.width
            anchors.verticalCenter: parent.verticalCenter
            width: trayRoot.drawerExtent
            height: root.barSize
            clip: true

            Row {
              id: trayIcons
              x: trayRoot.drawerExtent - trayRoot.revealExtent
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(17)
              layer.enabled: true

              Repeater {
                model: trayRoot.drawerItems
                TrayItem {}
              }
            }
          }
        }

        Row {
          id: pinnedRow
          x: drawerArea.x + horizontalTrayRoot.drawerBlockWidth
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(17)
          leftPadding: trayRoot.pinnedItems.length > 0 && trayRoot.allItems.length > 0 ? Style.space(6) : 0
          Repeater {
            model: trayRoot.pinnedItems
            TrayItem {}
          }
        }
      }
    }

    Component {
      id: verticalTray

      Item {
        id: verticalTrayRoot

        readonly property int pinnedHeight: pinnedCol.implicitHeight
        readonly property int drawerBlockHeight: trayRoot.allItems.length > 0 ? expandIcon.implicitHeight + trayRoot.drawerExtent : 0

        implicitWidth: root.barSize
        implicitHeight: pinnedHeight + drawerBlockHeight

        containmentMask: QtObject {
          function contains(point: point): bool {
            if (point.x < 0 || point.x > verticalTrayRoot.width) return false
            var chevronY = trayRoot.drawerExtent - trayRoot.revealExtent
            if (point.y >= chevronY && point.y <= verticalTrayRoot.drawerBlockHeight) return true
            var pinnedStart = verticalTrayRoot.drawerBlockHeight
            return point.y >= pinnedStart && point.y <= verticalTrayRoot.implicitHeight
          }
        }

        Item {
          id: drawerArea
          y: 0
          width: root.barSize
          height: verticalTrayRoot.drawerBlockHeight
          visible: trayRoot.allItems.length > 0

          HoverHandler {
            onHoveredChanged: trayRoot.expanded = hovered
          }

          ModuleButton {
            id: expandIcon
            width: implicitWidth
            height: implicitHeight
            y: trayRoot.drawerExtent - trayRoot.revealExtent
            text: ""
            textRotation: 90
            horizontalMargin: 9
            verticalPadding: 6
            onPressed: function(button) {
              if (button === Qt.RightButton) trayRoot.managePopupOpen = !trayRoot.managePopupOpen
            }
          }

          Item {
            id: trayClip
            y: expandIcon.height
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.barSize
            height: trayRoot.drawerExtent
            clip: true

            Column {
              id: trayIcons
              y: trayRoot.drawerExtent - trayRoot.revealExtent
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(17)
              layer.enabled: true

              Repeater {
                model: trayRoot.drawerItems
                TrayItem {}
              }
            }
          }
        }

        Column {
          id: pinnedCol
          y: drawerArea.y + verticalTrayRoot.drawerBlockHeight
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(17)
          topPadding: trayRoot.pinnedItems.length > 0 && trayRoot.allItems.length > 0 ? Style.space(6) : 0
          Repeater {
            model: trayRoot.pinnedItems
            TrayItem {}
          }
        }
      }
    }

    PopupCard {
      id: managePopup
      anchorItem: trayRoot
      owner: trayRoot
      bar: root
      open: trayRoot.managePopupOpen
      contentWidth: managePopup.fittedContentWidth(Style.space(300))
      contentHeight: managePopup.fittedContentHeight(manageColumn.implicitHeight)

      Column {
        id: manageColumn
        anchors.fill: parent
        spacing: Style.space(8)

        Text {
          text: "Tray icons"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          text: "Pinned icons stay visible. Hidden icons never show."
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          width: parent.width
        }

        Text {
          visible: trayRoot.allItems.length === 0
          text: "No tray items reporting."
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.italic: true
        }

        Repeater {
          model: trayRoot.allItems
          delegate: Item {
            id: rowRoot
            required property var modelData
            required property int index
            width: manageColumn.width
            implicitHeight: 28

            readonly property string itemId: String(modelData.id || "")
            readonly property string displayName: {
              var t = String(modelData.title || "").trim()
              if (t) return t
              var tt = String(modelData.tooltipTitle || "").trim()
              if (tt) return tt
              var id = String(modelData.id || "")
              var slash = id.lastIndexOf("/")
              return slash !== -1 ? id.substring(slash + 1) : (id || "Unknown")
            }
            readonly property bool isPinned: trayRoot.pinnedIds.indexOf(itemId) !== -1
            readonly property bool isHidden: trayRoot.hiddenIds.indexOf(itemId) !== -1

            IconImage {
              id: rowIcon
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              implicitSize: 16
              width: 16
              height: 16
              source: root.trayIconSource(rowRoot.modelData.icon)
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: rowIcon.right
              anchors.leftMargin: Style.space(10)
              anchors.right: rowHideBtn.left
              anchors.rightMargin: Style.space(8)
              text: rowRoot.displayName
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Button {
              id: rowPinBtn
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: parent.right
              iconText: ""
              text: rowRoot.isPinned ? "Unpin" : "Pin"
              foreground: root.foreground
              horizontalPadding: 8
              verticalPadding: 3
              iconSize: Style.font.bodySmall
              fontSize: Style.font.bodySmall
              onClicked: trayRoot.togglePin(rowRoot.itemId)
            }

            Button {
              id: rowHideBtn
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: rowPinBtn.left
              anchors.rightMargin: Style.space(6)
              iconText: ""
              text: rowRoot.isHidden ? "Show" : "Hide"
              foreground: root.foreground
              horizontalPadding: 8
              verticalPadding: 3
              iconSize: Style.font.bodySmall
              fontSize: Style.font.bodySmall
              onClicked: trayRoot.toggleHide(rowRoot.itemId)
            }
          }
        }
      }
    }
  }

  component TrayItem: Item {
    id: trayItemRoot

    required property var modelData

    visible: modelData.status !== Status.Passive
    implicitWidth: visible ? 16 : 0
    implicitHeight: visible ? 16 : 0

    IconImage {
      anchors.centerIn: parent
      implicitSize: 12
      width: 12
      height: 12
      source: root.trayIconSource(trayItemRoot.modelData.icon)
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.showTooltip(trayItemRoot, root.trayTooltip(modelData))
      onExited: root.hideTooltip(trayItemRoot)
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton && trayItemRoot.modelData.hasMenu) {
          var point = trayItemRoot.QsWindow.contentItem.mapFromItem(trayItemRoot, mouse.x, mouse.y)
          trayItemRoot.modelData.display(trayItemRoot.QsWindow.window, point.x, point.y)
        } else if (mouse.button === Qt.MiddleButton) {
          trayItemRoot.modelData.secondaryActivate()
        } else {
          trayItemRoot.modelData.activate()
        }
      }
      onWheel: function(wheel) {
        trayItemRoot.modelData.scroll(wheel.angleDelta.y, false)
      }
    }

    readonly property bool tooltipHovered: visible && opacity > 0 && mouseArea.containsMouse
  }

}
