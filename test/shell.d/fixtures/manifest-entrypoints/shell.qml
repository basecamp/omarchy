import QtQuick
import Quickshell

ShellRoot {
  id: root

  readonly property string resultPath: Quickshell.env("OMARCHY_QML_TEST_RESULT")
  readonly property string rootPath: Quickshell.env("OMARCHY_PATH")
  property var failures: []
  property var createdIds: []
  property var createdObjects: []
  property var panelBarIds: [
    "omarchy.audio",
    "omarchy.bluetooth",
    "omarchy.monitor",
    "omarchy.network",
    "omarchy.power",
    "omarchy.weather"
  ]

  function fail(message) {
    failures.push(String(message))
  }

  function assertTrue(condition, message) {
    if (!condition) fail(message)
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function writeResult() {
    var payload = JSON.stringify({
      ok: failures.length === 0,
      failures: failures,
      created: createdIds
    })

    if (resultPath) {
      Quickshell.execDetached(["bash", "-lc", "printf '%s' " + shellQuote(payload) + " > " + shellQuote(resultPath)])
    }
  }

  function manifests() {
    try {
      return JSON.parse(Qt.atob(Quickshell.env("OMARCHY_QML_MANIFESTS") || "W10="))
    } catch (error) {
      fail("manifest list failed to parse: " + error)
      return []
    }
  }

  function initialProperties(entry) {
    var props = {}
    if (entry.kind === "bar") {
      props.omarchyPath = rootPath
      props.barWidgetRegistry = fakeBarWidgetRegistry
      props.barConfig = {
        position: "top",
        transparent: false,
        centerAnchor: "",
        layout: { left: [], center: [], right: [] }
      }
      props.shell = mockShell
    } else if (entry.kind === "bar-widget" || panelBarIds.indexOf(entry.id) !== -1) {
      props.bar = fakeBar
      props.moduleName = entry.id
      props.settings = {}
    }
    return props
  }

  function injectProperties(item, entry) {
    if (!item) return
    if ("omarchyPath" in item) item.omarchyPath = rootPath
    if ("shell" in item) item.shell = mockShell
    if ("manifest" in item) item.manifest = entry.manifest
    if ("pluginRegistry" in item) item.pluginRegistry = mockPluginRegistry
    if ("barWidgetRegistry" in item) item.barWidgetRegistry = fakeBarWidgetRegistry
    if ("bar" in item) item.bar = fakeBar
    if ("moduleName" in item) item.moduleName = entry.id
    if ("settings" in item) item.settings = {}
    if ("service" in item) item.service = null
  }

  function loadEntry(entry) {
    var component = Qt.createComponent(entry.url, Component.PreferSynchronous)
    if (component.status !== Component.Ready) {
      fail(entry.id + " " + entry.kind + " failed to load: " + component.errorString())
      return
    }

    var item = component.createObject(host, initialProperties(entry))
    if (!item) {
      fail(entry.id + " " + entry.kind + " failed to instantiate: " + component.errorString())
      return
    }

    injectProperties(item, entry)
    createdObjects.push(item)
    createdIds.push(entry.id + ":" + entry.kind)
  }

  Item { id: host }

  QtObject {
    id: fakeBarWidgetRegistry
    property var widgets: ({})
    property int revision: 0
    signal changed()
    function register(id, component, metadata) {
      var next = {}
      for (var key in widgets) next[key] = widgets[key]
      next[String(id)] = { component: component, metadata: metadata || {} }
      widgets = next
      revision++
      changed()
    }
    function unregister(id) {
      var next = {}
      for (var key in widgets) if (key !== String(id)) next[key] = widgets[key]
      widgets = next
      revision++
      changed()
    }
    function metadataFor(id) { return widgets[String(id)] ? widgets[String(id)].metadata : null }
    function availableIds() { return Object.keys(widgets) }
    function has(id) { return widgets[String(id)] !== undefined }
  }

  QtObject {
    id: mockPluginRegistry
    property var installedPlugins: ({})
    function isEnabled(id) { return true }
    function entryPointUrl(manifest, kind) { return "" }
    function rescan() {}
  }

  QtObject {
    id: mockNotificationService
    property bool doNotDisturb: false
    property ListModel pendingModel: ListModel {}
    property ListModel pastModel: ListModel {}
    function setDoNotDisturb(value) { doNotDisturb = !!value }
  }

  QtObject {
    id: mockShell
    property var bar: fakeBar
    property var barConfig: ({ position: "top" })
    property var shellConfig: ({ version: 1, idle: {}, plugins: [], bar: { layout: { left: [], center: [], right: [] } } })
    function firstPartyServiceFor(id) {
      if (id === "omarchy.notifications") return mockNotificationService
      return null
    }
    function serviceFor(id) { return firstPartyServiceFor(id) }
    function summon(id, payloadJson) { return true }
    function hide(id) { return true }
    function toggle(id, payloadJson) { return true }
    function callIfLoaded(id, method, arg) { return "ok" }
    function mutateShellConfig(mutator) {}
    function updateEntryInline(moduleName, settings) { return true }
  }

  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 26
    property string omarchyPath: root.rootPath
    property string fontFamily: "monospace"
    property color foreground: "white"
    property color background: "black"
    property color urgent: "red"
    property var shell: mockShell
    function run(command) {}
    function showTooltip(target, text) {}
    function hideTooltip(target) {}
    function requestPopout(owner) {}
    function releasePopout(owner) {}
    function registerClickTarget(target) {}
    function unregisterClickTarget(target) {}
  }

  Timer {
    interval: 1
    running: true
    repeat: false
    onTriggered: {
      var entries = manifests()
      root.assertTrue(entries.length > 0, "manifest entry list is not empty")
      for (var i = 0; i < entries.length; i++) root.loadEntry(entries[i])

      Qt.callLater(function() {
        root.assertTrue(root.createdIds.length === entries.length, "all manifest entrypoints instantiate")
        for (var j = 0; j < root.createdObjects.length; j++) {
          var item = root.createdObjects[j]
          if (item && typeof item.destroy === "function") item.destroy()
        }
        root.writeResult()
      })
    }
  }
}
