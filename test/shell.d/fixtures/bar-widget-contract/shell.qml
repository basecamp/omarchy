import QtQuick
import Quickshell

ShellRoot {
  id: root

  readonly property string resultPath: Quickshell.env("OMARCHY_QML_TEST_RESULT")
  readonly property string rootPath: Quickshell.env("OMARCHY_PATH")
  property var failures: []
  property var createdIds: []
  property var createdObjects: []

  function fail(message) {
    failures.push(String(message))
  }

  function assertTrue(condition, message) {
    if (!condition) fail(message)
  }

  function assertEqual(actual, expected, message) {
    if (actual !== expected) fail(message + " expected=" + expected + " actual=" + actual)
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

  function widgets() {
    try {
      return JSON.parse(Qt.atob(Quickshell.env("OMARCHY_QML_BAR_WIDGETS") || "W10="))
    } catch (error) {
      fail("bar widget list failed to parse: " + error)
      return []
    }
  }

  function safeCall(item, method, entry) {
    if (!item || typeof item[method] !== "function") return
    try {
      item[method]()
    } catch (error) {
      fail(entry.id + " " + method + "() threw: " + error)
    }
  }

  function finiteDimension(value) {
    var n = Number(value)
    return isFinite(n) && n >= 0
  }

  function loadWidget(entry) {
    var component = Qt.createComponent(entry.url, Component.PreferSynchronous)
    if (component.status !== Component.Ready) {
      fail(entry.id + " failed to load: " + component.errorString())
      return
    }

    var item = component.createObject(host, {
      moduleName: entry.id,
      settings: {}
    })
    if (!item) {
      fail(entry.id + " failed to instantiate without bar: " + component.errorString())
      return
    }

    if ("bar" in item) {
      root.assertTrue(item.bar === null || item.bar === undefined, entry.id + " starts without injected bar")
      item.bar = fakeBar
      root.assertTrue(item.bar === fakeBar, entry.id + " accepts delayed bar injection")
    }
    if ("moduleName" in item) {
      item.moduleName = entry.id
      root.assertEqual(item.moduleName, entry.id, entry.id + " accepts moduleName injection")
    }
    if ("settings" in item) {
      item.settings = {}
      root.assertTrue(item.settings !== null && item.settings !== undefined, entry.id + " accepts settings injection")
    }
    if (typeof item.setting === "function") {
      root.assertEqual(item.setting("missing", "fallback"), "fallback", entry.id + " exposes setting fallback")
    }

    safeCall(item, "refresh", entry)
    safeCall(item, "close", entry)

    createdObjects.push(item)
    createdIds.push(entry.id)
  }

  Item { id: host }

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
      var entries = widgets()
      root.assertTrue(entries.length > 0, "bar widget list is not empty")
      for (var i = 0; i < entries.length; i++) root.loadWidget(entries[i])

      Qt.callLater(function() {
        for (var j = 0; j < root.createdObjects.length; j++) {
          var item = root.createdObjects[j]
          var id = root.createdIds[j]
          root.assertTrue(root.finiteDimension(item.implicitWidth), id + " has a finite implicitWidth")
          root.assertTrue(root.finiteDimension(item.implicitHeight), id + " has a finite implicitHeight")
          if (item && typeof item.destroy === "function") item.destroy()
        }
        root.assertTrue(root.createdIds.length === entries.length, "all bar widgets instantiate")
        root.writeResult()
      })
    }
  }
}
