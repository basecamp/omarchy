import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

ShellRoot {
  id: root

  property string home: Quickshell.env("HOME")
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || (home + "/.local/share/omarchy")
  property string omarchyConfigDir: home + "/.config/omarchy"
  property var builtinBarConfig: ({
    position: "top",
    fontFamily: "JetBrainsMono Nerd Font",
    centerAnchor: "clock",
    layout: {
      left: ["omarchy", "workspaces"],
      center: ["clock", "weather", "update", "voxtype", "screenRecording", "idle", "notifications"],
      right: ["tray", "bluetooth", "network", "audio", "cpu", "battery"]
    },
    modules: {
      clock: {
        format: "dddd HH:mm",
        formatAlt: "dd MMMM 'W'ww yyyy",
        verticalFormat: "HH\n—\nmm"
      }
    }
  })
  property var defaultBarConfig: builtinBarConfig
  property var userBarConfig: ({})
  property var layoutConfig: builtinBarConfig.layout
  property var moduleConfig: builtinBarConfig.modules
  property string centerAnchor: "clock"
  property int barConfigSerial: 0
  property string position: "top"
  property string fontFamily: "JetBrainsMono Nerd Font"
  property color foreground: "#cacccc"
  property color background: "#101315"
  property color urgent: "#a55555"
  property string weatherText: ""
  property string weatherClass: ""
  property bool updateAvailable: false
  property string voxtypeIcon: ""
  property string voxtypeClass: ""
  property string screenRecordingText: ""
  property string screenRecordingTooltip: ""
  property string idleText: ""
  property string idleTooltip: ""
  property string notificationSilencingText: ""
  property string notificationSilencingTooltip: ""
  property int audioVolumePercent: -1
  property string networkKind: "disconnected"
  property string networkLabel: ""
  property int networkSignal: -1
  property string networkFrequency: ""
  property bool clockAlt: false
  property var tooltipTarget: null
  property string tooltipText: ""
  property bool tooltipShown: false
  property var activePopout: null

  function requestPopout(owner) {
    if (activePopout === owner) return
    if (activePopout && "closePopout" in activePopout) activePopout.closePopout()
    activePopout = owner
  }

  function releasePopout(owner) {
    if (activePopout === owner) activePopout = null
  }

  readonly property bool vertical: position === "left" || position === "right"
  readonly property int barSize: vertical ? 28 : 26

  function normalizePosition(value) {
    var next = String(value || "").trim()
    return /^(top|bottom|left|right)$/.test(next) ? next : "top"
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function fileUrl(path) {
    return "file://" + path.split("/").map(encodeURIComponent).join("/")
  }

  function commandWithOmarchyPath(command) {
    return "OMARCHY_PATH=" + shellQuote(omarchyPath) + " " + command
  }

  function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
  }

  function cloneConfig(value) {
    if (Array.isArray(value)) {
      var arrayCopy = []
      for (var i = 0; i < value.length; i++)
        arrayCopy.push(cloneConfig(value[i]))
      return arrayCopy
    }

    if (isPlainObject(value)) {
      var objectCopy = {}
      for (var key in value)
        objectCopy[key] = cloneConfig(value[key])
      return objectCopy
    }

    return value
  }

  function mergeConfig(base, override) {
    var result = cloneConfig(base || {})
    if (!isPlainObject(override)) return result

    for (var key in override) {
      if (isPlainObject(result[key]) && isPlainObject(override[key]))
        result[key] = mergeConfig(result[key], override[key])
      else
        result[key] = cloneConfig(override[key])
    }

    return result
  }

  function parseConfig(raw, label) {
    var text = String(raw || "").trim()
    if (!text) return {}

    try {
      var parsed = JSON.parse(text)
      return isPlainObject(parsed) ? parsed : {}
    } catch (error) {
      console.warn("Failed to parse " + label + ": " + error)
      return {}
    }
  }

  function applyBarConfig() {
    var config = mergeConfig(defaultBarConfig, userBarConfig)

    position = normalizePosition(config.position)
    fontFamily = String(config.fontFamily || "JetBrainsMono Nerd Font")
    centerAnchor = String(config.centerAnchor || "clock")
    layoutConfig = isPlainObject(config.layout) ? config.layout : builtinBarConfig.layout
    moduleConfig = isPlainObject(config.modules) ? config.modules : {}
    barConfigSerial++
  }

  function loadDefaultBarConfig(raw) {
    defaultBarConfig = mergeConfig(builtinBarConfig, parseConfig(raw, "bar defaults"))
    applyBarConfig()
  }

  function loadUserBarConfig(raw) {
    userBarConfig = parseConfig(raw, "bar config")
    applyBarConfig()
  }

  function layoutModules(region) {
    var serial = barConfigSerial
    var modules = layoutConfig ? layoutConfig[region] : null
    return Array.isArray(modules) ? modules : []
  }

  function moduleSettings(name) {
    var serial = barConfigSerial
    var settings = moduleConfig ? moduleConfig[String(name)] : null
    return isPlainObject(settings) ? settings : {}
  }

  function moduleString(name, key, fallback) {
    var value = moduleSettings(name)[key]
    return value === undefined || value === null ? fallback : String(value)
  }

  function moduleIndex(modules, name) {
    if (!Array.isArray(modules)) return -1

    for (var i = 0; i < modules.length; i++) {
      if (String(modules[i]) === name)
        return i
    }

    return -1
  }

  function modulesBefore(modules, name) {
    var index = moduleIndex(modules, name)
    return index <= 0 ? [] : modules.slice(0, index)
  }

  function modulesAfter(modules, name) {
    var index = moduleIndex(modules, name)
    return index === -1 ? [] : modules.slice(index + 1)
  }

  function builtinModuleComponent(name) {
    switch (String(name)) {
    case "omarchy": return omarchyModuleComponent
    case "workspaces": return workspacesModuleComponent
    case "clock": return clockModuleComponent
    case "weather": return weatherModuleComponent
    case "update": return updateModuleComponent
    case "voxtype": return voxtypeModuleComponent
    case "screenRecording":
    case "screenrecording": return screenRecordingModuleComponent
    case "idle": return idleModuleComponent
    case "notifications":
    case "notificationSilencing": return notificationsModuleComponent
    case "tray": return trayModuleComponent
    case "bluetooth": return bluetoothModuleComponent
    case "network": return networkModuleComponent
    case "audio":
    case "pulseaudio": return audioModuleComponent
    case "cpu": return cpuModuleComponent
    case "battery": return batteryModuleComponent
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

  function customModuleType(name) {
    var settings = moduleSettings(name)
    var type = String(settings.type || "")
    if (type) return type
    if (settings.exec) return "command"
    if (settings.source) return "qml"
    return ""
  }

  function customModuleSource(name) {
    var settings = moduleSettings(name)
    var source = settings.source ? expandPath(settings.source) : ""
    if (!source && customModuleSafeName(name))
      source = omarchyConfigDir + "/bar/modules/" + String(name) + ".qml"

    return source ? fileUrl(source) : ""
  }

  readonly property var firstPartyWidgets: ({
    "media": true,
    "audioPanel": true,
    "networkPanel": true,
    "bluetoothPanel": true,
    "calendar": true,
    "notificationCenter": true,
    "brightness": true,
    "powerProfile": true,
    "systemStats": true,
    "weatherFlyout": true,
    "workspacesPro": true,
    "powerMenu": true,
    "idleInhibitor": true,
    "microphone": true,
    "notificationCenter": true,
    "activeWindow": true,
    "nightLight": true,
    "keyboardLayout": true,
    "lockKeys": true,
    "spacer": true
  })

  function firstPartyWidgetSource(name) {
    if (!firstPartyWidgets[String(name)]) return ""
    return fileUrl(omarchyPath + "/default/quickshell/bar/widgets/" + String(name) + ".qml")
  }

  function networkCommand() {
    return [
      "route_device=$(ip route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == \"dev\") { print $(i + 1); exit } }')",
      "connection_name() { command -v nmcli >/dev/null 2>&1 && nmcli -t -f GENERAL.CONNECTION device show \"$1\" 2>/dev/null | awk -F: '$1 == \"GENERAL.CONNECTION\" { print $2; exit }'; }",
      "wifi_details() { command -v nmcli >/dev/null 2>&1 && nmcli -t -f IN-USE,SIGNAL,FREQ device wifi list --rescan no 2>/dev/null | awk -F: '$1 == \"*\" { print $2 \"\\t\" $3; exit }'; }",
      "if [[ -n $route_device && ! -d /sys/class/net/$route_device/wireless ]]; then",
      "  label=$(connection_name \"$route_device\"); label=${label:-$route_device}",
      "  printf 'ethernet\\t%s\\t\\t\\n' \"$label\"",
      "elif [[ -n $route_device ]]; then",
      "  label=$(connection_name \"$route_device\"); label=${label:-$route_device}",
      "  details=$(wifi_details)",
      "  signal=${details%%$'\\t'*}",
      "  frequency=${details#*$'\\t'}",
      "  [[ $frequency == \"$details\" ]] && frequency=\"\"",
      "  printf 'wifi\\t%s\\t%s\\t%s\\n' \"$label\" \"$signal\" \"$frequency\"",
      "else",
      "  printf 'disconnected\\t\\t\\t\\n'",
      "fi"
    ].join("\n")
  }

  function run(command) {
    if (!command) return

    launcher.command = ["bash", "-lc", command]
    launcher.startDetached()
  }

  function runProcess(process) {
    if (!process.running)
      process.running = true
  }

  function showTooltip(target, text) {
    if (!text) return

    tooltipTarget = target
    tooltipText = text
    tooltipShown = false
    tooltipTimer.restart()
  }

  function hideTooltip(target) {
    if (tooltipTarget !== target) return

    tooltipTimer.stop()
    tooltipTarget = null
    tooltipText = ""
    tooltipShown = false
  }

  function parseModuleJson(raw) {
    var text = String(raw || "").trim()
    if (!text) return {}

    var lines = text.split("\n")
    try {
      return JSON.parse(lines[lines.length - 1])
    } catch (error) {
      return { text: text }
    }
  }

  function loadTheme(raw) {
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (!match) continue

      if (match[1] === "foreground") foreground = match[2]
      else if (match[1] === "background") background = match[2]
      else if (match[1] === "red") urgent = match[2]
    }
  }

  function updateWeather(raw) {
    var data = parseModuleJson(raw)
    weatherText = data.text || ""
    weatherClass = data.class || ""
  }

  function updateIndicator(name, raw) {
    var data = parseModuleJson(raw)
    var text = data.text || ""
    var tooltip = data.tooltip || ""

    if (name === "screenRecording") {
      screenRecordingText = text
      screenRecordingTooltip = tooltip
    } else if (name === "idle") {
      idleText = text
      idleTooltip = tooltip
    } else if (name === "notifications") {
      notificationSilencingText = text
      notificationSilencingTooltip = tooltip
    }
  }

  function updateVoxtype(raw) {
    var data = parseModuleJson(raw)
    var state = data.alt || data.class || "idle"

    voxtypeClass = state
    if (state === "recording") voxtypeIcon = "󰍬"
    else if (state === "transcribing") voxtypeIcon = "󰔟"
    else voxtypeIcon = ""
  }

  function updateNetwork(raw) {
    var parts = String(raw || "disconnected\t\t\t").replace(/\r?\n+$/, "").split("\t")
    networkKind = parts[0] || "disconnected"
    networkLabel = parts[1] || ""
    networkSignal = parts[2] ? parseInt(parts[2], 10) : -1
    networkFrequency = parts[3] || ""
  }

  function refreshWeather() {
    runProcess(weatherProc)
  }

  function refreshUpdate() {
    runProcess(updateProc)
  }

  function refreshScreenRecording() {
    runProcess(screenRecordingProc)
  }

  function refreshIndicators() {
    refreshScreenRecording()
    runProcess(idleProc)
    runProcess(notificationSilencingProc)
  }

  function refreshNetwork() {
    runProcess(networkProc)
  }

  function updateAudioVolume(raw) {
    var volume = parseInt(String(raw || "").trim(), 10)
    audioVolumePercent = isNaN(volume) ? -1 : Math.max(0, volume)
  }

  function refreshAudio() {
    runProcess(audioProc)
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

  function activeTrayItemCount() {
    var count = 0
    var values = SystemTray.items.values

    for (var i = 0; i < values.length; i++) {
      if (values[i].status !== Status.Passive)
        count++
    }

    return count
  }

  function batteryIcon() {
    var device = UPower.displayDevice
    if (!device || !device.isPresent) return ""

    var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
    var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
    var index = Math.max(0, Math.min(9, Math.floor(device.percentage / 10)))

    if (device.state === UPowerDeviceState.FullyCharged) return "󰂅"
    if (!UPower.onBattery && device.state !== UPowerDeviceState.Charging) return ""
    if (device.state === UPowerDeviceState.Charging) return chargingIcons[index]
    return defaultIcons[index]
  }

  function audioIcon() {
    var sink = Pipewire.defaultAudioSink
    if (!sink || !sink.audio) return ""
    if (sink.audio.muted) return ""

    var props = sink.properties || {}
    var sinkText = String([
      sink.name,
      sink.description,
      sink.nickname,
      props["device.icon-name"],
      props["device.product.name"],
      props["node.name"]
    ].join(" ")).toLowerCase()

    if (sinkText.indexOf("headphone") !== -1 || sinkText.indexOf("headset") !== -1)
      return ""

    var volume = sink.audio.volume
    if (!isFinite(volume) && audioVolumePercent >= 0)
      volume = audioVolumePercent / 100
    if (!isFinite(volume)) return ""
    if (volume < 0.34) return ""
    if (volume < 0.67) return ""
    return ""
  }

  function bluetoothIcon() {
    var adapter = Bluetooth.defaultAdapter
    if (!adapter) return ""
    if (!adapter.enabled) return "󰂲"

    var devices = Bluetooth.devices.values
    for (var i = 0; i < devices.length; i++) {
      if (devices[i].connected)
        return "󰂱"
    }

    return ""
  }

  function networkIcon() {
    if (networkKind === "wifi") {
      var icons = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
      var index = Math.max(0, Math.min(4, Math.ceil(networkSignal / 20) - 1))
      return icons[index]
    }

    if (networkKind === "ethernet") return "󰀂"
    return "󰤮"
  }

  function networkTooltip() {
    if (networkKind === "wifi") {
      var frequency = parseFloat(networkFrequency)
      var frequencyText = frequency > 0 ? " (" + (frequency / 1000).toFixed(1) + " GHz)" : ""
      return (networkLabel || "Wi-Fi") + frequencyText
    }

    if (networkKind === "ethernet") return "Connected"
    return "Disconnected"
  }

  function audioTooltip() {
    var sink = Pipewire.defaultAudioSink
    if (sink && sink.audio) {
      var volume = sink.audio.volume
      if (isFinite(volume))
        return "Playing at " + Math.round(volume * 100) + "%"
    }

    if (audioVolumePercent >= 0)
      return "Playing at " + audioVolumePercent + "%"

    return "Audio"
  }

  function bluetoothTooltip() {
    var count = 0
    var devices = Bluetooth.devices.values

    for (var i = 0; i < devices.length; i++) {
      if (devices[i].connected)
        count++
    }

    return "Devices connected: " + count
  }

  function batteryTooltip() {
    var device = UPower.displayDevice
    if (!device || !device.isPresent) return ""

    var direction = UPower.onBattery ? "↓" : "↑"
    return Math.round(device.changeRate) + "W" + direction + " " + Math.round(device.percentage) + "%"
  }

  function trayIconSource(icon) {
    var value = String(icon || "")
    var marker = "?path="
    var markerIndex = value.indexOf(marker)
    if (markerIndex === -1) return value

    var name = value.substring(0, markerIndex).split("/").pop()
    var iconPath = value.substring(markerIndex + marker.length).split("&")[0]
    return fileUrl(iconPath + "/hicolor/16x16/status/" + name + ".png")
  }

  function trayTooltip(item) {
    return item.tooltipTitle || item.title || item.id || ""
  }

  function focusWorkspace(id) {
    root.run("hyprctl dispatch " + shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  function clockText() {
    if (clockAlt)
      return Qt.formatDateTime(systemClock.date, moduleString("clock", "formatAlt", "dd MMMM 'W'ww yyyy"))

    if (vertical)
      return Qt.formatDateTime(systemClock.date, moduleString("clock", "verticalFormat", "HH\n—\nmm"))

    return Qt.formatDateTime(systemClock.date, moduleString("clock", "format", "dddd HH:mm"))
  }

  SystemClock {
    id: systemClock
    precision: SystemClock.Minutes
  }

  Process { id: launcher }

  Timer {
    id: tooltipTimer
    interval: 400
    onTriggered: root.tooltipShown = true
  }

  FileView {
    path: root.omarchyPath + "/default/quickshell/bar/bar-defaults.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadDefaultBarConfig(text())
    onFileChanged: {
      reload()
      root.loadDefaultBarConfig(text())
    }
  }

  FileView {
    path: root.omarchyConfigDir + "/bar.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadUserBarConfig(text())
    onFileChanged: {
      reload()
      root.loadUserBarConfig(text())
    }
  }

  FileView {
    path: root.home + "/.config/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadTheme(text())
    onFileChanged: {
      reload()
      root.loadTheme(text())
    }
  }

  Process {
    id: weatherProc
    command: ["bash", "-lc", root.commandWithOmarchyPath(root.shellQuote(root.omarchyPath + "/default/waybar/weather.sh"))]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateWeather(text)
    }
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshWeather()
  }

  Process {
    id: updateProc
    command: ["bash", "-lc", root.commandWithOmarchyPath("omarchy-update-available")]
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

  Process {
    id: voxtypeProc
    command: ["bash", "-lc", "omarchy-voxtype-status"]
    running: true
    stdout: SplitParser {
      onRead: function(data) {
        root.updateVoxtype(data)
      }
    }
  }

  Process {
    id: screenRecordingProc
    command: ["bash", "-lc", root.commandWithOmarchyPath(root.shellQuote(root.omarchyPath + "/default/waybar/indicators/screen-recording.sh"))]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateIndicator("screenRecording", text)
    }
  }

  Process {
    id: idleProc
    command: ["bash", "-lc", root.commandWithOmarchyPath(root.shellQuote(root.omarchyPath + "/default/waybar/indicators/idle.sh"))]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateIndicator("idle", text)
    }
  }

  Process {
    id: notificationSilencingProc
    command: ["bash", "-lc", root.commandWithOmarchyPath(root.shellQuote(root.omarchyPath + "/default/waybar/indicators/notification-silencing.sh"))]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateIndicator("notifications", text)
    }
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshIndicators()
  }

  Process {
    id: networkProc
    command: ["bash", "-lc", root.commandWithOmarchyPath(root.networkCommand())]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateNetwork(text)
    }
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshNetwork()
  }

  Process {
    id: audioProc
    command: ["bash", "-lc", "if command -v pamixer >/dev/null; then pamixer --get-volume; elif command -v wpctl >/dev/null; then wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{ print int($2 * 100) }'; fi"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateAudioVolume(text)
    }
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshAudio()
  }

  IpcHandler {
    target: "bar"

    function refreshUpdate(): void {
      root.refreshUpdate()
    }

    function refreshScreenRecording(): void {
      root.refreshScreenRecording()
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

    anchors {
      top: root.position === "top" || root.vertical
      bottom: root.position === "bottom" || root.vertical
      left: root.position === "left" || !root.vertical
      right: root.position === "right" || !root.vertical
    }

    implicitWidth: root.vertical ? root.barSize : 0
    implicitHeight: root.vertical ? 0 : root.barSize
    color: root.background
    WlrLayershell.namespace: "omarchy-bar"
    WlrLayershell.layer: WlrLayer.Top

    Loader {
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalBar : horizontalBar
    }

    PopupWindow {
      id: tooltipWindow

      visible: root.tooltipShown && root.tooltipTarget !== null && root.tooltipText !== ""
      color: "transparent"
      implicitWidth: tooltipBubble.implicitWidth
      implicitHeight: tooltipBubble.implicitHeight

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
          if (!target) return

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
        color: root.background
        border.color: root.foreground
        border.width: 1
        radius: 0
        opacity: 0.97

        Text {
          id: tooltipLabel
          anchors.centerIn: parent
          text: root.tooltipText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: 12
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
          anchors.leftMargin: 8
          anchors.verticalCenter: parent.verticalCenter
        }

        RightModules {
          anchors.right: parent.right
          anchors.rightMargin: 8
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
          anchors.topMargin: 8
          anchors.horizontalCenter: parent.horizontalCenter
        }

        RightModules {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 8
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }
    }
  }

  Component { id: emptyModuleComponent; Item { implicitWidth: 0; implicitHeight: 0; visible: false } }
  Component { id: omarchyModuleComponent; OmarchyModule {} }
  Component { id: workspacesModuleComponent; WorkspacesModule {} }
  Component { id: clockModuleComponent; ClockModule {} }
  Component { id: weatherModuleComponent; WeatherModule {} }
  Component { id: updateModuleComponent; UpdateModule {} }
  Component { id: voxtypeModuleComponent; VoxtypeModule {} }
  Component { id: screenRecordingModuleComponent; ScreenRecordingModule {} }
  Component { id: idleModuleComponent; IdleModule {} }
  Component { id: notificationsModuleComponent; NotificationsModule {} }
  Component { id: trayModuleComponent; TrayModule {} }
  Component { id: bluetoothModuleComponent; BluetoothModule {} }
  Component { id: networkModuleComponent; NetworkModule {} }
  Component { id: audioModuleComponent; AudioModule {} }
  Component { id: cpuModuleComponent; CpuModule {} }
  Component { id: batteryModuleComponent; BatteryModule {} }

  component LeftModules: ModuleList {
    modules: root.layoutModules("left")
  }

  component RightModules: ModuleList {
    modules: root.layoutModules("right")
  }

  component CenterModules: Item {
    id: centerRoot

    property var modules: root.layoutModules("center")
    readonly property bool hasAnchor: root.moduleIndex(modules, root.centerAnchor) !== -1

    Loader {
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalCenterModules : horizontalCenterModules
    }

    Component {
      id: horizontalCenterModules

      Item {
        anchors.fill: parent

        ModuleList {
          visible: !centerRoot.hasAnchor
          modules: centerRoot.modules
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          modules: root.modulesBefore(centerRoot.modules, root.centerAnchor)
          anchors.right: centerAnchorModule.left
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          moduleName: root.centerAnchor
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          modules: root.modulesAfter(centerRoot.modules, root.centerAnchor)
          anchors.left: centerAnchorModule.right
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }
      }
    }

    Component {
      id: verticalCenterModules

      Item {
        anchors.fill: parent

        ModuleList {
          visible: !centerRoot.hasAnchor
          modules: centerRoot.modules
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          modules: root.modulesBefore(centerRoot.modules, root.centerAnchor)
          anchors.bottom: centerAnchorModule.top
          anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          moduleName: root.centerAnchor
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          modules: root.modulesAfter(centerRoot.modules, root.centerAnchor)
          anchors.top: centerAnchorModule.bottom
          anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        }
      }
    }
  }

  component ModuleList: Loader {
    id: moduleListRoot

    property var modules: []

    visible: modules.length > 0
    sourceComponent: root.vertical ? verticalModuleList : horizontalModuleList
    width: item ? item.implicitWidth : 0
    height: item ? item.implicitHeight : 0

    Component {
      id: horizontalModuleList

      Row {
        spacing: 0

        Repeater {
          model: moduleListRoot.modules

          ModuleSlot {
            required property var modelData
            moduleName: String(modelData)
          }
        }
      }
    }

    Component {
      id: verticalModuleList

      Column {
        spacing: 0

        Repeater {
          model: moduleListRoot.modules

          ModuleSlot {
            required property var modelData
            moduleName: String(modelData)
          }
        }
      }
    }
  }

  component ModuleSlot: Item {
    id: slot

    required property string moduleName
    readonly property string customType: root.customModuleType(moduleName)
    readonly property var builtinComponent: customType ? null : root.builtinModuleComponent(moduleName)
    readonly property string firstPartySource: customType || builtinComponent ? "" : root.firstPartyWidgetSource(moduleName)
    readonly property bool qmlCustom: customType === "qml"
    readonly property bool commandCustom: customType === "command"
    readonly property bool firstParty: firstPartySource !== ""
    readonly property var activeItem: qmlCustom || firstParty ? qmlLoader.item : componentLoader.item

    implicitWidth: activeItem && activeItem.visible ? activeItem.implicitWidth : 0
    implicitHeight: activeItem && activeItem.visible ? activeItem.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight

    Loader {
      id: componentLoader
      active: !slot.qmlCustom && !slot.firstParty
      sourceComponent: slot.builtinComponent || (slot.commandCustom ? customCommandModuleComponent : emptyModuleComponent)
      anchors.fill: parent
    }

    Loader {
      id: qmlLoader
      active: slot.qmlCustom || slot.firstParty
      source: slot.qmlCustom ? root.customModuleSource(slot.moduleName) : (slot.firstParty ? slot.firstPartySource : "")
      anchors.fill: parent
      onLoaded: slot.injectProps()
    }

    function injectProps() {
      var target = qmlLoader.item
      if (!target) return
      if ("bar" in target) target.bar = root
      if ("moduleName" in target) target.moduleName = moduleName
      if ("settings" in target) target.settings = root.moduleSettings(moduleName)
    }

    Connections {
      target: root
      function onBarConfigSerialChanged() { slot.injectProps() }
    }

    Component {
      id: customCommandModuleComponent
      CustomCommandModule { moduleName: slot.moduleName }
    }
  }

  component CustomCommandModule: ModuleButton {
    id: customRoot

    required property string moduleName
    property var settings: root.moduleSettings(moduleName)
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
      command: ["bash", "-lc", root.commandWithOmarchyPath(String(customRoot.setting("exec", "")))]
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
    property real fontSize: 12
    property real horizontalMargin: 7.5
    property real verticalPadding: 6
    property real textRotation: 0
    property real fixedWidth: -1
    property real fixedHeight: -1
    property string tooltipText: ""

    signal pressed(int button)
    signal wheelMoved(int delta)

    visible: text !== "" || keepSpace
    opacity: text === "" ? 0 : 1
    implicitWidth: fixedWidth > 0 ? fixedWidth : (root.vertical ? root.barSize : Math.max(12, label.implicitWidth + horizontalMargin * 2))
    implicitHeight: fixedHeight > 0 ? fixedHeight : (root.vertical ? Math.max(12, label.implicitHeight + verticalPadding * 2) : root.barSize)

    Text {
      id: label
      anchors.centerIn: parent
      text: buttonRoot.text
      color: buttonRoot.active ? root.urgent : root.foreground
      font.family: buttonRoot.fontFamily
      font.pixelSize: buttonRoot.fontSize
      rotation: buttonRoot.textRotation
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      onEntered: root.showTooltip(buttonRoot, buttonRoot.tooltipText)
      onExited: root.hideTooltip(buttonRoot)
      onClicked: function(mouse) { buttonRoot.pressed(mouse.button) }
      onWheel: function(wheel) { buttonRoot.wheelMoved(wheel.angleDelta.y) }
    }
  }

  component IndicatorModule: ModuleButton {
    fontSize: 10
    horizontalMargin: 5
    verticalPadding: 5
  }

  component OmarchyModule: ModuleButton {
    text: "\ue900"
    fontFamily: "omarchy"
    horizontalMargin: 7.5
    tooltipText: "Omarchy Menu\n\nSuper + Alt + Space"
    onPressed: function(button) {
      if (button === Qt.RightButton) root.run("xdg-terminal-exec")
      else root.run("env -u OMARCHY_PATH " + root.shellQuote(root.home + "/.local/share/omarchy/bin/omarchy-menu"))
    }
  }

  component WorkspacesModule: GridLayout {
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : 3
    rowSpacing: root.vertical ? 3 : 0

    Repeater {
      model: root.workspaceIds()

      ModuleButton {
        required property int modelData

        property var workspace: root.workspaceById(modelData)
        property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        text: focused ? "󱓻" : (modelData === 10 ? "0" : String(modelData))
        opacity: occupied || modelData <= 5 || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : 24
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

  component WeatherModule: ModuleButton {
    text: root.weatherText
    active: root.weatherClass === "active"
    keepSpace: false
    horizontalMargin: 7.5
    onPressed: function() { root.run("omarchy-notification-send \"$(omarchy-weather-status)\"") }
  }

  component UpdateModule: ModuleButton {
    text: root.updateAvailable ? "" : ""
    fontSize: 10
    tooltipText: root.updateAvailable ? "Omarchy update available" : ""
    onPressed: function() { root.run("omarchy-launch-floating-terminal-with-presentation omarchy-update") }
  }

  component VoxtypeModule: ModuleButton {
    text: root.voxtypeIcon
    active: root.voxtypeClass === "recording"
    tooltipText: root.voxtypeClass
    onPressed: function(button) {
      if (button === Qt.RightButton) root.run("omarchy-voxtype-config")
      else root.run("omarchy-voxtype-model")
    }
  }

  component ScreenRecordingModule: IndicatorModule {
    text: root.screenRecordingText
    active: root.screenRecordingText !== ""
    tooltipText: root.screenRecordingTooltip
    onPressed: function() { root.run("omarchy-capture-screenrecording") }
  }

  component IdleModule: IndicatorModule {
    text: root.idleText
    active: root.idleText !== ""
    tooltipText: root.idleTooltip
    onPressed: function() { root.run("omarchy-toggle-idle") }
  }

  component NotificationsModule: IndicatorModule {
    text: root.notificationSilencingText
    active: root.notificationSilencingText !== ""
    tooltipText: root.notificationSilencingTooltip
    onPressed: function() { root.run("omarchy-toggle-notification-silencing") }
  }

  component TrayModule: Item {
    id: trayRoot

    property bool expanded: false
    readonly property int activeItems: root.activeTrayItemCount()
    readonly property int drawerExtent: activeItems > 0 ? activeItems * 16 + (activeItems - 1) * 17 : 0
    // Match Waybar's group/tray-expander drawer transition-duration.
    readonly property int animationDuration: 600
    property real revealProgress: expanded ? 1 : 0
    readonly property real revealExtent: drawerExtent * revealProgress

    Behavior on revealProgress {
      NumberAnimation { duration: trayRoot.animationDuration; easing.type: Easing.OutCubic }
    }

    containmentMask: QtObject {
      function contains(point: point): bool {
        if (root.vertical)
          return point.x >= 0 && point.x <= trayRoot.width && point.y >= trayRoot.drawerExtent - trayRoot.revealExtent && point.y <= trayRoot.height

        return point.x >= trayRoot.drawerExtent - trayRoot.revealExtent && point.x <= trayRoot.width && point.y >= 0 && point.y <= trayRoot.height
      }
    }

    visible: activeItems > 0
    clip: false
    implicitWidth: root.vertical ? root.barSize : trayContent.implicitWidth
    implicitHeight: root.vertical ? trayContent.implicitHeight : root.barSize

    Loader {
      id: trayContent
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalTray : horizontalTray
    }

    HoverHandler {
      onHoveredChanged: trayRoot.expanded = hovered
    }

    Component {
      id: horizontalTray

      Item {
        id: horizontalTrayRoot

        implicitWidth: expandIcon.implicitWidth + trayRoot.drawerExtent
        implicitHeight: root.barSize

        ModuleButton {
          id: expandIcon
          width: implicitWidth
          height: implicitHeight
          x: trayRoot.drawerExtent - trayRoot.revealExtent
          text: ""
          horizontalMargin: 9
          verticalPadding: 6

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
            spacing: 17
            layer.enabled: true

            Repeater {
              model: SystemTray.items
              TrayItem {}
            }
          }
        }

      }
    }

    Component {
      id: verticalTray

      Item {
        id: verticalTrayRoot

        implicitWidth: root.barSize
        implicitHeight: expandIcon.implicitHeight + trayRoot.drawerExtent

        ModuleButton {
          id: expandIcon
          width: implicitWidth
          height: implicitHeight
          y: trayRoot.drawerExtent - trayRoot.revealExtent
          text: ""
          textRotation: 90
          horizontalMargin: 9
          verticalPadding: 6

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
            spacing: 17
            layer.enabled: true

            Repeater {
              model: SystemTray.items
              TrayItem {}
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
  }

  component BluetoothModule: ModuleButton {
    text: root.bluetoothIcon()
    horizontalMargin: 8.5
    visible: Bluetooth.defaultAdapter !== null
    tooltipText: root.bluetoothTooltip()
    onPressed: function() { root.run("omarchy-launch-bluetooth") }
  }

  component NetworkModule: ModuleButton {
    text: root.networkIcon()
    horizontalMargin: 6.5
    tooltipText: root.networkTooltip()
    onPressed: function() { root.run("OMARCHY_PATH=" + root.shellQuote(root.omarchyPath) + " PATH=" + root.shellQuote(root.omarchyPath + "/bin:" + (Quickshell.env("PATH") || "")) + " " + root.shellQuote(root.omarchyPath + "/bin/omarchy-launch-wifi")) }
  }

  component AudioModule: ModuleButton {
    text: root.audioIcon()
    tooltipText: root.audioTooltip()
    onPressed: function(button) {
      if (button === Qt.RightButton) root.run("pamixer -t")
      else root.run("omarchy-launch-audio")
    }
    onWheelMoved: function(delta) {
      if (delta > 0) root.run("pamixer -i 5")
      else if (delta < 0) root.run("pamixer -d 5")
      root.refreshAudio()
    }
  }

  component CpuModule: ModuleButton {
    text: "󰍛"
    onPressed: function(button) {
      if (button === Qt.RightButton) root.run("alacritty")
      else root.run("omarchy-launch-or-focus-tui btop")
    }
  }

  component BatteryModule: ModuleButton {
    property var device: UPower.displayDevice

    text: root.batteryIcon()
    visible: device !== null && device.isPresent && device.percentage > 0
    active: device !== null && device.percentage <= 20 && UPower.onBattery
    tooltipText: root.batteryTooltip()
    onPressed: function(button) {
      if (button === Qt.RightButton) root.run("omarchy-notification-send \"$(omarchy-battery-status)\"")
      else root.run("omarchy-menu power")
    }
  }
}
