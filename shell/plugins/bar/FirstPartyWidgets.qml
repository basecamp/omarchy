import QtQuick

QtObject {
  id: root

  required property var barWidgetRegistry

  readonly property var metadata: ({
    "omarchy":            { displayName: "Omarchy menu",       description: "Launches the Omarchy menu",                 category: "Compositor", allowMultiple: false },
    "workspaces":         { displayName: "Workspaces",         description: "Workspace number indicators",               category: "Compositor", allowMultiple: false },
    "media":              { displayName: "Media",              description: "MPRIS now-playing with playback controls",   category: "Media",    allowMultiple: false },
    "audioPanel":         { displayName: "Audio",              description: "Volume slider, output picker, per-app mixer", category: "Audio",    allowMultiple: false, sourceDir: "../panels", sourceName: "Audio" },
    "monitorPanel":       { displayName: "Display",            description: "Brightness slider and laptop display controls", category: "System",   allowMultiple: false, sourceDir: "../panels", sourceName: "Monitor" },
    "networkPanel":       { displayName: "Network",            description: "Wi-Fi list and connection state",            category: "Network",  allowMultiple: false, sourceDir: "../panels", sourceName: "Network" },
    "powerPanel":         { displayName: "Power",              description: "Battery, power profile, and system stats",    category: "System",   allowMultiple: false, sourceDir: "../panels", sourceName: "Power" },
    "bluetoothPanel":     { displayName: "Bluetooth",          description: "Bluetooth device list with connect/disconnect", category: "Network", allowMultiple: false, sourceDir: "../panels", sourceName: "Bluetooth" },
    "clock":              { displayName: "Clock",              description: "Day/time label; click to toggle alternate format", category: "Time",  allowMultiple: false, settingsForm: "clockSettings" },
    "indicators":         { displayName: "Indicators",         description: "Manual state indicators",                     category: "Status",   allowMultiple: false },
    "notificationCenter": { displayName: "Notification center", description: "Recent notifications + DND",                category: "Status",   allowMultiple: false },
    "systemUpdate":       { displayName: "System update",       description: "Indicates available system updates",         category: "System",   allowMultiple: false },
    "systemStats":        { displayName: "System stats",       description: "CPU icon — hover for graphs, click to open btop", category: "System", allowMultiple: false },
    "tray":               { displayName: "System tray",        description: "Status notifier items",                       category: "Status",   allowMultiple: false },
    "weather":            { displayName: "Weather",            description: "Weather pill with detail popup",              category: "Info",     allowMultiple: false, settingsForm: "weatherSettings" },
    "microphone":         { displayName: "Microphone",         description: "Mic input state and mute toggle",             category: "Audio",    allowMultiple: false },
    "activeWindow":       { displayName: "Active window",      description: "Title of the focused window",                 category: "Compositor", allowMultiple: false },
    "keyboardLayout":     { displayName: "Keyboard layout",    description: "Current xkb layout, click cycles",            category: "Compositor", allowMultiple: false },
    "lockKeys":           { displayName: "Lock keys",          description: "Caps / Num / Scroll lock indicators",          category: "System",   allowMultiple: false },
    "spacer":             { displayName: "Spacer",             description: "Configurable blank space",                    category: "Layout",   allowMultiple: true,  settingsForm: "spacerSettings" }
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
