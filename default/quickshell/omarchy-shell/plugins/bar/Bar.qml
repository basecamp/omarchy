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
import qs.Commons
import "common" as BarCommon

Item {
  id: root

  // The omarchy-shell host injects omarchyPath when it instantiates this Bar.
  // Default fallback keeps the file loadable in isolation (e.g. for QML tooling).
  required property string omarchyPath
  // Injected by the host shell. Shared with the bar settings panel so both
  // see the same widget catalogue.
  required property var barWidgetRegistry
  // Injected by the host shell every time shell.json is reloaded. Holds the
  // `bar:` subtree: position, centerAnchor, layout. The host owns file IO;
  // the bar just renders whatever it's handed. The bar font follows the
  // OS-level fontconfig monospace binding — it is not stored in shell.json.
  required property var barConfig
  // Injected by the host shell so the bar can detect Noctalia-compat plugins
  // and look up manifests when wiring per-widget Noctalia pluginApi.
  property var pluginRegistry: null
  // Injected by the host shell. Used so Noctalia plugins that reach for
  // shell-wide APIs (openPanel, currentScreen) can do so via pluginApi.
  property var shell: null
  // Mirrors the on-disk `bar-off` flag so the user can hide the bar without
  // killing the entire shell. Wired to BarPanel.visible below; updated by the
  // FileView watcher further down.
  property bool barHidden: false
  property string home: Quickshell.env("HOME")
  property string omarchyConfigDir: home + "/.config/omarchy"
  property var fallbackBarConfig: ({
    position: "top",
    centerAnchor: "calendar",
    layout: { left: [], center: [], right: [] }
  })
  property var layoutConfig: fallbackBarConfig.layout
  property string centerAnchor: ""
  property int barConfigSerial: 0
  property string position: "top"
  // "monospace" resolves through fontconfig at paint time, so changing the
  // system font (via `omarchy-font-set`) updates the bar without a reload.
  property string fontFamily: "monospace"
  // Bound to the central Color singleton so the bar tracks shell.toml's
  // [bar] section. Property names kept for the rest of this file's bindings.
  property color foreground: Color.bar.text
  property color background: Color.bar.background
  property color urgent: Color.bar.active
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

  // -------------------------------------------------- Noctalia compat helpers
  //
  // The shell owns pluginApi creation and Main.qml service instantiation now;
  // bar widgets just look up their api by moduleName. Keeping section/index
  // helpers here because they're needed for Noctalia bar-widget injection
  // (widgetId, section, sectionWidgetIndex, sectionWidgetsCount).

  function sectionOfEntry(entry) {
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var list = layoutConfig[sections[s]] || []
      for (var i = 0; i < list.length; i++) {
        if (list[i] === entry) return sections[s]
      }
    }
    return ""
  }

  function indexOfEntry(entry) {
    var section = sectionOfEntry(entry)
    var list = section ? (layoutConfig[section] || []) : []
    for (var i = 0; i < list.length; i++) if (list[i] === entry) return i
    return -1
  }

  function entriesOfSection(section) {
    return Array.isArray(layoutConfig[section]) ? layoutConfig[section] : []
  }

  function noctaliaPluginApiFor(moduleName) {
    if (!shell || typeof shell.noctaliaPluginApiFor !== "function") return null
    return shell.noctaliaPluginApiFor(moduleName)
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

  function normalizeLayoutEntry(entry) {
    if (typeof entry === "string") return { id: entry }
    if (isPlainObject(entry) && entry.id) return entry
    return null
  }

  function normalizeLayoutSection(list) {
    if (!Array.isArray(list)) return []
    var result = []
    for (var i = 0; i < list.length; i++) {
      var normalized = normalizeLayoutEntry(list[i])
      if (normalized) result.push(normalized)
    }
    return result
  }

  function normalizeLayout(layout) {
    if (!isPlainObject(layout)) layout = fallbackBarConfig.layout
    return {
      left: pinTrayToInner(normalizeLayoutSection(layout.left), "left"),
      center: pinTrayToInner(normalizeLayoutSection(layout.center), "center"),
      right: pinTrayToInner(normalizeLayoutSection(layout.right), "right")
    }
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
    var config = isPlainObject(barConfig) ? barConfig : fallbackBarConfig

    position = normalizePosition(config.position)
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
    if (!isPlainObject(entry)) return {}
    var copy = {}
    for (var key in entry) {
      if (key === "id") continue
      copy[key] = entry[key]
    }
    return copy
  }

  function entryId(entry) {
    if (typeof entry === "string") return entry
    if (isPlainObject(entry) && entry.id) return String(entry.id)
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

    return source ? fileUrl(source) : ""
  }

  // First-party widgets are registered with the BarWidgetRegistry at startup.
  // Each entry maps a widget id to its display metadata; the QML source lives
  // at widgets/<id>.qml and is loaded asynchronously via Qt.createComponent.
  readonly property var firstPartyWidgetMetadata: ({
    "media":              { displayName: "Media",              description: "MPRIS now-playing with playback controls",   category: "Media",    allowMultiple: false },
    "audioPanel":         { displayName: "Audio",              description: "Volume slider, output picker, per-app mixer", category: "Audio",    allowMultiple: false },
    "networkPanel":       { displayName: "Network",            description: "Wi-Fi list and connection state",            category: "Network",  allowMultiple: false },
    "bluetoothPanel":     { displayName: "Bluetooth",          description: "Bluetooth device list with connect/disconnect", category: "Network", allowMultiple: false },
    "calendar":           { displayName: "Calendar",           description: "Clock with month-grid popup",                  category: "Time",     allowMultiple: false, settingsForm: "calendarSettings" },
    "notificationCenter": { displayName: "Notification center", description: "Recent notifications + DND",  category: "Status",   allowMultiple: false },
    "systemStats":        { displayName: "System stats",       description: "CPU icon — hover for graphs, click to open btop", category: "System",   allowMultiple: false },
    "weatherFlyout":      { displayName: "Weather",            description: "Weather pill with detail popup",              category: "Info",     allowMultiple: false, settingsForm: "weatherSettings" },
    "idleInhibitor":      { displayName: "Keep awake",         description: "Toggle idle inhibitor",                       category: "System",   allowMultiple: false },
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
    var url = Qt.resolvedUrl("widgets/" + id + ".qml")
    var meta = firstPartyWidgetMetadata[id] || {}
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

  function networkCommand() {
    return [
      "device=$(ip route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == \"dev\") { print $(i + 1); exit } }')",
      "if [[ -z $device ]]; then",
      "  printf 'disconnected\\t\\t\\t\\n'",
      "  exit 0",
      "fi",
      "if [[ ! -d /sys/class/net/$device/wireless ]]; then",
      "  printf 'ethernet\\t%s\\t\\t\\n' \"$device\"",
      "  exit 0",
      "fi",
      "show=$(iwctl station \"$device\" show 2>/dev/null | sed -e 's/\\x1b\\[[0-9;]*m//g')",
      "state=$(awk '/^[[:space:]]*State[[:space:]]/ { sub(/.*State[[:space:]]+/, \"\"); sub(/[[:space:]]+$/, \"\"); print; exit }' <<<\"$show\")",
      "ssid=$(awk '/^[[:space:]]*Connected network[[:space:]]/ { sub(/.*Connected network[[:space:]]+/, \"\"); sub(/[[:space:]]+$/, \"\"); print; exit }' <<<\"$show\")",
      "freq=$(awk '/^[[:space:]]*Frequency[[:space:]]/ { sub(/.*Frequency[[:space:]]+/, \"\"); sub(/[[:space:]]+$/, \"\"); print; exit }' <<<\"$show\")",
      "rssi=$(awk '/^[[:space:]]*RSSI[[:space:]]/ { sub(/.*RSSI[[:space:]]+/, \"\"); sub(/[[:space:]]+$/, \"\"); print; exit }' <<<\"$show\")",
      "dbm=${rssi%% *}",
      "signal=\"\"",
      "if [[ -n $dbm ]]; then",
      "  if (( dbm >= -50 )); then signal=100",
      "  elif (( dbm <= -100 )); then signal=0",
      "  else signal=$(( 2 * (dbm + 100) )); fi",
      "fi",
      "if [[ -n $state && $state != connected ]]; then",
      "  printf 'disconnected\\t\\t\\t\\n'",
      "  exit 0",
      "fi",
      "printf 'wifi\\t%s\\t%s\\t%s\\n' \"${ssid:-$device}\" \"$signal\" \"$freq\""
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
    var state = String(data.alt || data.class || "idle")

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
    var index = Math.max(0, Math.min(9, Math.floor(device.percentage * 10)))

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
    return Math.round(device.changeRate) + "W" + direction + " " + Math.round(device.percentage * 100) + "%"
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
    onTriggered: root.tooltipShown = true
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
    id: weatherProc
    command: ["bash", "-lc", root.commandWithOmarchyPath(root.shellQuote(root.omarchyPath + "/default/quickshell/omarchy-shell/scripts/weather.sh"))]
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
    command: ["bash", "-lc", root.commandWithOmarchyPath("omarchy-voxtype-status")]
    running: true
    stdout: SplitParser {
      onRead: function(data) {
        root.updateVoxtype(data)
      }
    }
  }

  Process {
    id: screenRecordingProc
    command: ["bash", "-lc", root.commandWithOmarchyPath(root.shellQuote(root.omarchyPath + "/default/quickshell/omarchy-shell/scripts/indicators/screen-recording.sh"))]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateIndicator("screenRecording", text)
    }
  }

  Process {
    id: idleProc
    command: ["bash", "-lc", root.commandWithOmarchyPath(root.shellQuote(root.omarchyPath + "/default/quickshell/omarchy-shell/scripts/indicators/idle.sh"))]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateIndicator("idle", text)
    }
  }

  Process {
    id: notificationSilencingProc
    command: ["bash", "-lc", root.commandWithOmarchyPath(root.shellQuote(root.omarchyPath + "/default/quickshell/omarchy-shell/scripts/indicators/notification-silencing.sh"))]
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

    visible: !root.barHidden

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
      return w[moduleName] ? w[moduleName].component : null
    }
    readonly property bool qmlCustom: customType === "qml"
    readonly property bool commandCustom: customType === "command"
    readonly property bool registered: registryComponent !== null
    readonly property var activeItem: {
      if (registered) return registryLoader.item
      if (qmlCustom) return qmlLoader.item
      return componentLoader.item
    }

    implicitWidth: activeItem && activeItem.visible ? activeItem.implicitWidth : 0
    implicitHeight: activeItem && activeItem.visible ? activeItem.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight

    Loader {
      id: componentLoader
      active: !slot.qmlCustom && !slot.registered
      sourceComponent: slot.builtinComponent || (slot.commandCustom ? customCommandModuleComponent : emptyModuleComponent)
      anchors.fill: parent
    }

    Loader {
      id: registryLoader
      active: slot.registered
      sourceComponent: slot.registered ? slot.registryComponent : null
      anchors.fill: parent
      onLoaded: slot.injectProps()
    }

    Loader {
      id: qmlLoader
      active: slot.qmlCustom
      source: slot.qmlCustom ? root.customModuleSource(slot.entry) : ""
      anchors.fill: parent
      onLoaded: slot.injectProps()
    }

    onModuleSettingsChanged: injectProps()

    function injectProps() {
      var target = registryLoader.item || qmlLoader.item
      if (!target) return
      if ("bar" in target) target.bar = root
      if ("moduleName" in target) target.moduleName = moduleName
      if ("settings" in target) target.settings = moduleSettings

      // Noctalia compat injection. Only kicks in for plugins whose manifest
      // was translated from Noctalia shape; for our first-party widgets these
      // properties don't exist on the target item so nothing happens.
      var manifest = root.pluginRegistry ? root.pluginRegistry.installedPlugins[moduleName] : null
      if (manifest && manifest.__noctaliaCompat) {
        if ("pluginApi" in target)            target.pluginApi          = root.noctaliaPluginApiFor(moduleName)
        if ("widgetId" in target)             target.widgetId           = moduleName
        if ("section" in target)              target.section            = root.sectionOfEntry(entry)
        if ("sectionWidgetIndex" in target)   target.sectionWidgetIndex = root.indexOfEntry(entry)
        if ("sectionWidgetsCount" in target)  target.sectionWidgetsCount = root.entriesOfSection(root.sectionOfEntry(entry)).length
        if ("screen" in target && root.QsWindow && root.QsWindow.window)
          target.screen = root.QsWindow.window.screen
      }
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
    property real rightExtraMargin: 0
    property real verticalPadding: 6
    property real textRotation: 0
    property real fixedWidth: -1
    property real fixedHeight: -1
    property string tooltipText: ""

    signal pressed(int button)
    signal wheelMoved(int delta)

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
      font.pointSize: buttonRoot.fontSize * 0.75
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
    onPressed: function(button) {
      if (button === Qt.RightButton) root.run("xdg-terminal-exec")
      else root.run("omarchy-shell-ipc menu toggle root")
    }
  }

  component WorkspacesModule: GridLayout {
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : 2
    rowSpacing: root.vertical ? 2 : 0

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
    property bool managePopupOpen: false
    function closePopout() { managePopupOpen = false }

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
              spacing: 17
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
          spacing: 17
          leftPadding: trayRoot.pinnedItems.length > 0 && trayRoot.allItems.length > 0 ? 6 : 0
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
              spacing: 17
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
          spacing: 17
          topPadding: trayRoot.pinnedItems.length > 0 && trayRoot.allItems.length > 0 ? 6 : 0
          Repeater {
            model: trayRoot.pinnedItems
            TrayItem {}
          }
        }
      }
    }

    BarCommon.PopupCard {
      id: managePopup
      anchorItem: trayRoot
      owner: trayRoot
      bar: root
      open: trayRoot.managePopupOpen
      contentWidth: 300
      contentHeight: manageColumn.implicitHeight + 28

      Column {
        id: manageColumn
        anchors.fill: parent
        spacing: 8

        Text {
          text: "Tray icons"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: 12
          font.bold: true
        }

        Text {
          text: "Pinned icons stay visible. Hidden icons never show."
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: 10
          wrapMode: Text.WordWrap
          width: parent.width
        }

        Text {
          visible: trayRoot.allItems.length === 0
          text: "No tray items reporting."
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: 11
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
              anchors.leftMargin: 10
              anchors.right: rowHideBtn.left
              anchors.rightMargin: 8
              text: rowRoot.displayName
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 11
              elide: Text.ElideRight
            }

            BarCommon.PillButton {
              id: rowPinBtn
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: parent.right
              iconText: ""
              text: rowRoot.isPinned ? "Unpin" : "Pin"
              foreground: root.foreground
              horizontalPadding: 8
              verticalPadding: 3
              iconSize: 11
              fontSize: 11
              onClicked: trayRoot.togglePin(rowRoot.itemId)
            }

            BarCommon.PillButton {
              id: rowHideBtn
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: rowPinBtn.left
              anchors.rightMargin: 6
              iconText: ""
              text: rowRoot.isHidden ? "Show" : "Hide"
              foreground: root.foreground
              horizontalPadding: 8
              verticalPadding: 3
              iconSize: 11
              fontSize: 11
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
  }

  component BluetoothModule: ModuleButton {
    text: root.bluetoothIcon()
    horizontalMargin: 8.5
    visible: Bluetooth.defaultAdapter !== null
    onPressed: function() { root.run("omarchy-launch-bluetooth") }
  }

  component NetworkModule: ModuleButton {
    text: root.networkIcon()
    horizontalMargin: 6.5
    rightExtraMargin: 2
    tooltipText: root.networkTooltip()
    onPressed: function() { root.run("OMARCHY_PATH=" + root.shellQuote(root.omarchyPath) + " PATH=" + root.shellQuote(root.omarchyPath + "/bin:" + (Quickshell.env("PATH") || "")) + " " + root.shellQuote(root.omarchyPath + "/bin/omarchy-launch-wifi")) }
  }

  component AudioModule: ModuleButton {
    text: root.audioIcon()
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
    horizontalMargin: 8.5
    visible: device !== null && device.isPresent && device.percentage > 0
    active: device !== null && device.percentage <= 0.2 && UPower.onBattery
    tooltipText: root.batteryTooltip()
    onPressed: function(button) {
      if (button === Qt.RightButton) root.run("omarchy-notification-send \"$(omarchy-battery-status)\"")
      else root.run("omarchy-shell-ipc menu toggle power")
    }
  }
}
