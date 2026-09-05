import QtQuick
import Quickshell
import qs.Commons

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
    if (entry.id === "omarchy.agents") {
      root.assertTrue(typeof item.iconCandidatesForProvider === "function", entry.id + " resolves provider marks by convention")
      var darkIcons = item.iconCandidatesForProvider({ providerId: "codex" }, Qt.color("#1a1b26")).join(" ")
      var lightIcons = item.iconCandidatesForProvider({ providerId: "codex" }, Qt.color("#ffffff")).join(" ")
      root.assertTrue(darkIcons.indexOf("codex.svg") >= 0 && darkIcons.indexOf("codex-light.svg") < 0, entry.id + " uses the dark-theme Codex icon on dark surfaces")
      root.assertTrue(lightIcons.indexOf("codex-light.svg") >= 0, entry.id + " prefers the light-theme Codex icon on light surfaces")
    }

    safeCall(item, "refresh", entry)
    safeCall(item, "close", entry)

    createdObjects.push(item)
    createdIds.push(entry.id)
  }

  Item { id: host }

  // Second weather instance, opted into showTemperature, checked in both
  // orientations alongside the generic contract loop below.
  property var weatherTempWidget: null

  function loadWeatherTempVariant(entries) {
    for (var e = 0; e < entries.length; e++) {
      if (entries[e].id !== "omarchy.weather") continue
      var component = Qt.createComponent(entries[e].url, Component.PreferSynchronous)
      if (component.status !== Component.Ready) {
        fail("omarchy.weather showTemperature variant failed to load: " + component.errorString())
        return
      }
      weatherTempWidget = component.createObject(host, {
        moduleName: "omarchy.weather",
        settings: { showTemperature: true }
      })
      // createObject() can return null on an instantiation-time error even
      // after Ready; record it rather than letting the guarded checks below
      // skip and the file still pass.
      if (!weatherTempWidget) {
        fail("omarchy.weather showTemperature variant failed to instantiate: " + component.errorString())
        return
      }
      weatherTempWidget.bar = fakeBar
      return
    }
    fail("omarchy.weather is missing from the bar widget list")
  }

  QtObject {
    id: mockShell
    property var bar: fakeBar
    property var barConfig: ({ position: "top" })
    property var shellConfig: ({ version: 1, idle: {}, plugins: [], bar: { layout: { left: [], center: [], right: [] } } })
    function firstPartyServiceFor(id) { return null }
    function serviceFor(id) { return null }
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
      root.loadWeatherTempVariant(entries)

      Qt.callLater(function() {
        for (var j = 0; j < root.createdObjects.length; j++) {
          var item = root.createdObjects[j]
          var id = root.createdIds[j]
          root.assertTrue(root.finiteDimension(item.implicitWidth), id + " has a finite implicitWidth")
          root.assertTrue(root.finiteDimension(item.implicitHeight), id + " has a finite implicitHeight")
          if (id === "omarchy.weather")
            root.assertEqual(item.openPanelIndicatorWidth, 0, "omarchy.weather leaves the open-panel mark on the slot fallback when icon-only")
        }

        if (root.weatherTempWidget) {
          root.assertTrue(root.weatherTempWidget.showTemperature === true,
            "omarchy.weather composes the temperature label on a horizontal bar when showTemperature is set")
          root.assertTrue(root.finiteDimension(root.weatherTempWidget.implicitWidth),
            "omarchy.weather showTemperature variant has a finite implicitWidth")
          root.assertTrue(root.finiteDimension(root.weatherTempWidget.openPanelIndicatorWidth),
            "omarchy.weather temperature variant exposes a finite open-panel indicator width tied to the label")
        }

        fakeBar.vertical = true
        fakeBar.barSize = Style.bar.sizeVertical

        Qt.callLater(function() {
          for (var k = 0; k < root.createdObjects.length; k++) {
            var verticalItem = root.createdObjects[k]
            var verticalId = root.createdIds[k]
            if (verticalId === "omarchy.clock")
              root.assertEqual(verticalItem.implicitHeight, Style.bar.iconSlot * 3, verticalId + " uses one slot per line")
            else if (verticalId === "omarchy.weather" || verticalId === "omarchy.system-update")
              root.assertEqual(verticalItem.implicitHeight, Style.bar.statusSlot, verticalId + " uses one compact status slot")
            if (verticalItem && typeof verticalItem.destroy === "function") verticalItem.destroy()
          }

          if (root.weatherTempWidget) {
            root.assertTrue(root.weatherTempWidget.showTemperature === false,
              "omarchy.weather forces icon-only on a vertical bar even with showTemperature set")
            root.assertEqual(root.weatherTempWidget.implicitHeight, Style.bar.statusSlot,
              "omarchy.weather keeps the compact status slot on a vertical bar with showTemperature set")
            if (typeof root.weatherTempWidget.destroy === "function") root.weatherTempWidget.destroy()
          }

          root.assertTrue(root.createdIds.length === entries.length, "all bar widgets instantiate")
          root.writeResult()
        })
      })
    }
  }
}
