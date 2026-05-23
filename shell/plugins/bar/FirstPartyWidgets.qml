import QtQuick

QtObject {
  id: root

  required property var barWidgetRegistry

  readonly property var metadata: ({
    "omarchy.menu":            { displayName: "Omarchy menu",       description: "Launches the Omarchy menu",                 category: "Compositor", allowMultiple: false, sourceName: "Omarchy", legacyId: "Omarchy" },
    "omarchy.workspaces":      { displayName: "Workspaces",         description: "Workspace number indicators",               category: "Compositor", allowMultiple: false, sourceName: "Workspaces", legacyId: "Workspaces" },
    "omarchy.media":           { displayName: "Media",              description: "MPRIS now-playing with playback controls",   category: "Media",    allowMultiple: false, sourceName: "Media", legacyId: "Media" },
    "omarchy.audio":           { displayName: "Audio",              description: "Volume slider, output picker, per-app mixer", category: "Audio",    allowMultiple: false, sourceDir: "../panels", sourceName: "Audio", legacyId: "AudioPanel" },
    "omarchy.monitor":         { displayName: "Display",            description: "Brightness slider and laptop display controls", category: "System",   allowMultiple: false, sourceDir: "../panels", sourceName: "Monitor", legacyId: "MonitorPanel" },
    "omarchy.network":         { displayName: "Network",            description: "Wi-Fi list and connection state",            category: "Network",  allowMultiple: false, sourceDir: "../panels", sourceName: "Network", legacyId: "NetworkPanel" },
    "omarchy.power":           { displayName: "Power",              description: "Battery, power profile, and system stats",    category: "System",   allowMultiple: false, sourceDir: "../panels", sourceName: "Power", legacyId: "PowerPanel" },
    "omarchy.bluetooth":       { displayName: "Bluetooth",          description: "Bluetooth device list with connect/disconnect", category: "Network", allowMultiple: false, sourceDir: "../panels", sourceName: "Bluetooth", legacyId: "BluetoothPanel" },
    "omarchy.clock":           { displayName: "Clock",              description: "Day/time label; click to toggle alternate format", category: "Time",  allowMultiple: false, sourceName: "Clock", settingsForm: "clockSettings", legacyId: "Clock" },
    "omarchy.indicators":      { displayName: "Indicators",         description: "Manual state indicators",                     category: "Status",   allowMultiple: true, sourceName: "Indicators", legacyId: "Indicators",
      schema: [
        { key: "items", type: "multiselect", label: "Indicators", description: "Choose which indicators this widget instance should show. Leave empty to show all indicators.", noSelectionText: "All indicators", placeholderText: "Search indicators...", emptyText: "No indicators",
          options: [
            { value: "Dnd", label: "Do not disturb", description: "Notification silencing" },
            { value: "NightLight", label: "Night light", description: "Blue-light filter" },
            { value: "StayAwake", label: "Stay awake", description: "Idle lock and screensaver override" },
            { value: "ScreenRecording", label: "Screen recording", description: "GPU screen recorder status" },
            { value: "Dictation", label: "Dictation", description: "Voice typing status" }
          ] },
        { key: "alwaysShow", type: "boolean", label: "Always Show", description: "Show inactive indicators without waiting for hover.", defaultValue: false }
      ] },
    "omarchy.notifications":   { displayName: "Notification center", description: "Recent notifications + DND",                category: "Status",   allowMultiple: false, sourceName: "NotificationCenter", legacyId: "NotificationCenter" },
    "omarchy.system-update":   { displayName: "System update",       description: "Indicates available system updates",         category: "System",   allowMultiple: false, sourceName: "SystemUpdate", legacyId: "SystemUpdate" },
    "omarchy.system-stats":    { displayName: "System stats",       description: "CPU icon — hover for graphs, click to open btop", category: "System", allowMultiple: false, sourceName: "SystemStats", legacyId: "SystemStats" },
    "omarchy.tray":            { displayName: "System tray",        description: "Status notifier items",                       category: "Status",   allowMultiple: false, sourceName: "Tray", legacyId: "Tray" },
    "omarchy.weather":         { displayName: "Weather",            description: "Weather pill with detail popup",              category: "Info",     allowMultiple: false, sourceName: "Weather", settingsForm: "weatherSettings", legacyId: "Weather" },
    "omarchy.microphone":      { displayName: "Microphone",         description: "Mic input state and mute toggle",             category: "Audio",    allowMultiple: false, sourceName: "Microphone", legacyId: "Microphone" },
    "omarchy.active-window":   { displayName: "Active window",      description: "Title of the focused window",                 category: "Compositor", allowMultiple: false, sourceName: "ActiveWindow", legacyId: "ActiveWindow" },
    "omarchy.keyboard-layout": { displayName: "Keyboard layout",    description: "Current xkb layout, click cycles",            category: "Compositor", allowMultiple: false, sourceName: "KeyboardLayout", legacyId: "KeyboardLayout" },
    "omarchy.lock-keys":       { displayName: "Lock keys",          description: "Caps / Num / Scroll lock indicators",          category: "System",   allowMultiple: false, sourceName: "LockKeys", legacyId: "LockKeys" },
    "omarchy.spacer":          { displayName: "Spacer",             description: "Configurable blank space",                    category: "Layout",   allowMultiple: true,  sourceName: "Spacer", settingsForm: "spacerSettings", legacyId: "Spacer" }
  })

  property var registeredComponents: ({})

  Component.onCompleted: registerWidgets()

  function registerWidgets() {
    var ids = Object.keys(metadata)
    for (var i = 0; i < ids.length; i++) {
      var id = ids[i]
      if (barWidgetRegistry.has(id)) continue
      registerOne(id)
    }
  }

  function registerOne(id) {
    var meta = metadata[id] || {}
    var sourceDir = meta.sourceDir || "widgets"
    var sourceName = meta.sourceName || id
    var url = Qt.resolvedUrl(sourceDir + "/" + sourceName + ".qml")
    var enrichedMeta = {
      displayName: meta.displayName || id,
      description: meta.description || "",
      category: meta.category || "Misc",
      allowMultiple: meta.allowMultiple === true,
      settingsForm: meta.settingsForm || "",
      schema: Array.isArray(meta.schema) ? meta.schema : [],
      source: "first-party",
      legacyId: meta.legacyId || ""
    }
    var comp = Qt.createComponent(url, Component.Asynchronous)
    function finalize() {
      if (comp.status === Component.Ready) {
        barWidgetRegistry.register(id, comp, enrichedMeta)
        var next = ({})
        for (var k in registeredComponents) next[k] = registeredComponents[k]
        next[id] = comp
        registeredComponents = next
      } else if (comp.status === Component.Error) {
        console.warn("first-party widget " + id + " failed to load: " + comp.errorString())
      }
    }
    if (comp.status === Component.Loading) comp.statusChanged.connect(finalize)
    else finalize()
  }
}
