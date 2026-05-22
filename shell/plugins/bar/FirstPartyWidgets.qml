import QtQuick

QtObject {
  id: root

  required property var barWidgetRegistry

  readonly property var metadata: ({
    "Omarchy":            { displayName: "Omarchy menu",       description: "Launches the Omarchy menu",                 category: "Compositor", allowMultiple: false },
    "Workspaces":         { displayName: "Workspaces",         description: "Workspace number indicators",               category: "Compositor", allowMultiple: false },
    "Media":              { displayName: "Media",              description: "MPRIS now-playing with playback controls",   category: "Media",    allowMultiple: false },
    "AudioPanel":         { displayName: "Audio",              description: "Volume slider, output picker, per-app mixer", category: "Audio",    allowMultiple: false, sourceDir: "../panels", sourceName: "Audio" },
    "MonitorPanel":       { displayName: "Display",            description: "Brightness slider and laptop display controls", category: "System",   allowMultiple: false, sourceDir: "../panels", sourceName: "Monitor" },
    "NetworkPanel":       { displayName: "Network",            description: "Wi-Fi list and connection state",            category: "Network",  allowMultiple: false, sourceDir: "../panels", sourceName: "Network" },
    "PowerPanel":         { displayName: "Power",              description: "Battery, power profile, and system stats",    category: "System",   allowMultiple: false, sourceDir: "../panels", sourceName: "Power" },
    "BluetoothPanel":     { displayName: "Bluetooth",          description: "Bluetooth device list with connect/disconnect", category: "Network", allowMultiple: false, sourceDir: "../panels", sourceName: "Bluetooth" },
    "Clock":              { displayName: "Clock",              description: "Day/time label; click to toggle alternate format", category: "Time",  allowMultiple: false, settingsForm: "clockSettings" },
    "Indicators":         { displayName: "Indicators",         description: "Manual state indicators",                     category: "Status",   allowMultiple: true,
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
    "NotificationCenter": { displayName: "Notification center", description: "Recent notifications + DND",                category: "Status",   allowMultiple: false },
    "SystemUpdate":       { displayName: "System update",       description: "Indicates available system updates",         category: "System",   allowMultiple: false },
    "SystemStats":        { displayName: "System stats",       description: "CPU icon — hover for graphs, click to open btop", category: "System", allowMultiple: false },
    "Tray":               { displayName: "System tray",        description: "Status notifier items",                       category: "Status",   allowMultiple: false },
    "Weather":            { displayName: "Weather",            description: "Weather pill with detail popup",              category: "Info",     allowMultiple: false, settingsForm: "weatherSettings" },
    "Microphone":         { displayName: "Microphone",         description: "Mic input state and mute toggle",             category: "Audio",    allowMultiple: false },
    "ActiveWindow":       { displayName: "Active window",      description: "Title of the focused window",                 category: "Compositor", allowMultiple: false },
    "KeyboardLayout":     { displayName: "Keyboard layout",    description: "Current xkb layout, click cycles",            category: "Compositor", allowMultiple: false },
    "LockKeys":           { displayName: "Lock keys",          description: "Caps / Num / Scroll lock indicators",          category: "System",   allowMultiple: false },
    "Spacer":             { displayName: "Spacer",             description: "Configurable blank space",                    category: "Layout",   allowMultiple: true,  settingsForm: "spacerSettings" }
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
      source: "first-party"
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
