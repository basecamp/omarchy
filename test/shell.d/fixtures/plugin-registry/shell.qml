import QtQuick
import Quickshell
import "services"

ShellRoot {
  id: root

  readonly property string resultPath: Quickshell.env("OMARCHY_QML_TEST_RESULT")
  property var failures: []
  property int changeCount: 0
  property var config: ({
    version: 1,
    bar: { layout: { left: [], center: [], right: [] } },
    plugins: []
  })

  function fail(message) {
    failures.push(String(message))
  }

  function assertTrue(condition, message) {
    if (!condition) fail(message)
  }

  function assertEqual(actual, expected, message) {
    if (actual !== expected) fail(message + " expected=" + expected + " actual=" + actual)
  }

  function assertDeepEqual(actual, expected, message) {
    var actualJson = JSON.stringify(actual)
    var expectedJson = JSON.stringify(expected)
    if (actualJson !== expectedJson) fail(message + " expected=" + expectedJson + " actual=" + actualJson)
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function writeResult() {
    var payload = JSON.stringify({
      ok: failures.length === 0,
      failures: failures,
      changeCount: changeCount,
      config: config,
      ids: Object.keys(registry.installedPlugins).sort()
    })

    if (resultPath) {
      Quickshell.execDetached(["bash", "-lc", "printf '%s' " + shellQuote(payload) + " > " + shellQuote(resultPath)])
    }
  }

  function manifest(id, kinds, entryPoints) {
    return {
      schemaVersion: 1,
      id: id,
      name: id,
      version: "1.0.0",
      kinds: kinds,
      entryPoints: entryPoints
    }
  }

  function block(kind, source, payload) {
    return "===" + kind + "::" + source + "===\n"
      + (typeof payload === "string" ? payload : JSON.stringify(payload))
      + "\n=== EOM ===\n"
  }

  function has(id) {
    return registry.installedPlugins[String(id)] !== undefined
  }

  function pluginIds() {
    return Object.keys(registry.installedPlugins).sort()
  }

  function runChecks() {
    var scan = ""
    scan += block("firstparty", "/first/widgets/clock", manifest("omarchy.first-widget", ["bar-widget"], { barWidget: "Widget.qml" }))
    scan += block("firstparty", "/first/bar", manifest("omarchy.bar", ["bar"], { bar: "Bar.qml" }))
    scan += block("firstparty", "/first/panels/grouped", manifest("omarchy.grouped-panel", ["panel"], { panel: "Panel.qml" }))
    scan += block("thirdparty", "/third/panel", manifest("third.panel", ["panel"], { panel: "Panel.qml" }))
    scan += block("thirdparty", "/third/widget", manifest("third.widget", ["bar-widget"], { barWidget: "Widget.qml" }))
    scan += block("thirdparty", "/third/bar", manifest("third.bar", ["bar"], { bar: "Bar.qml" }))
    scan += block("thirdparty", "/third/shadow", manifest("omarchy.first-widget", ["panel"], { panel: "Panel.qml" }))
    scan += block("thirdparty", "/third/reserved", manifest("omarchy.reserved", ["panel"], { panel: "Panel.qml" }))
    scan += block("thirdparty", "/third/unsafe", manifest("third.unsafe", ["panel"], { panel: "../Panel.qml" }))
    scan += block("thirdparty", "/third/missing", { schemaVersion: 1, id: "third.missing", name: "missing", version: "1.0.0", kinds: ["panel"] })
    scan += block("thirdparty", "/third/schema", { schemaVersion: 2, id: "third.schema", name: "schema", version: "1.0.0", kinds: ["panel"], entryPoints: { panel: "Panel.qml" } })
    scan += block("thirdparty", "/third/bad-json", "{")

    registry.parseScanOutput(scan)

    root.assertDeepEqual(pluginIds(), [
      "omarchy.bar",
      "omarchy.first-widget",
      "omarchy.grouped-panel",
      "third.bar",
      "third.panel",
      "third.widget"
    ], "registry merges valid first-party and third-party manifests")

    root.assertTrue(registry.installedPlugins["omarchy.first-widget"].__isFirstParty === true, "first-party manifests are stamped")
    root.assertTrue(registry.installedPlugins["third.panel"].__isFirstParty === false, "third-party manifests are stamped")
    root.assertEqual(registry.installedPlugins["omarchy.grouped-panel"].__sourceDir, "/first/panels/grouped", "grouped plugin source paths are preserved")
    root.assertEqual(registry.entryPointUrl(registry.installedPlugins["third.panel"], "panel"), "file:///third/panel/Panel.qml", "entryPointUrl resolves plugin-relative paths")
    root.assertEqual(registry.entryPointUrl(registry.installedPlugins["third.widget"], "barWidget"), "file:///third/widget/Widget.qml", "entryPointUrl resolves bar widget paths")

    root.assertTrue(!has("omarchy.reserved"), "third-party omarchy namespace ids are rejected")
    root.assertTrue(!has("third.unsafe"), "unsafe entry points are rejected")
    root.assertTrue(!has("third.missing"), "incomplete manifests are rejected")
    root.assertTrue(!has("third.schema"), "unsupported schema versions are rejected")

    root.assertTrue(registry.isEnabled("omarchy.first-widget"), "first-party plugins are implicitly enabled")
    root.assertTrue(registry.isEnabled("omarchy.bar"), "built-in bar option is active by default")
    root.assertTrue(!registry.isEnabled("third.bar"), "third-party bar options start inactive")
    root.assertTrue(!registry.isEnabled("third.panel"), "third-party plugins start disabled")

    registry.setEnabled("third.bar", true)
    root.assertEqual(root.config.bar.id, "third.bar", "enabling third-party bar options writes bar id")
    root.assertTrue(registry.isEnabled("third.bar"), "selected third-party bar options are enabled")
    root.assertTrue(!registry.isEnabled("omarchy.bar"), "selecting third-party bar options deactivates built-in bar")
    registry.setEnabled("third.bar", false)
    root.assertTrue(root.config.bar.id === undefined, "disabling active bar options resets to built-in")
    root.assertTrue(registry.isEnabled("omarchy.bar"), "built-in bar option returns after reset")

    registry.setEnabled("third.panel", true)
    root.assertDeepEqual(root.config.plugins, [{ id: "third.panel" }], "enabling third-party panels writes plugins array")
    root.assertTrue(registry.isEnabled("third.panel"), "enabled third-party panels are found")
    registry.setEnabled("third.panel", false)
    root.assertDeepEqual(root.config.plugins, [], "disabling third-party panels removes plugins array entry")

    registry.setEnabled("third.widget", true)
    root.assertDeepEqual(root.config.bar.layout.right, [{ id: "third.widget" }], "enabling bar widgets appends to right layout")
    root.assertTrue(registry.isEnabled("third.widget"), "enabled bar widgets are found")
    registry.setEnabled("third.widget", false)
    root.assertDeepEqual(root.config.bar.layout.right, [], "disabling bar widgets removes layout entry")

    root.config = {
      version: 1,
      bar: { layout: { left: [], center: [{ id: "third.widget", size: 4 }], right: [] } },
      plugins: []
    }
    root.assertTrue(registry.isEnabled("third.widget"), "existing layout entries enable bar widgets")
    registry.setEnabled("third.widget", false)
    root.assertDeepEqual(root.config.bar.layout.center, [], "disabling existing bar widgets removes the original layout entry")

    root.config = { version: 1 }
    registry.setEnabled("third.panel", true)
    root.assertDeepEqual(root.config.plugins, [{ id: "third.panel" }], "setEnabled repairs missing plugin config shape")

    root.assertTrue(changeCount > 0, "registry emits change notifications")
    writeResult()
  }

  PluginRegistry {
    id: registry
    firstPartyDir: ""
    pluginsDir: Quickshell.env("HOME") + "/.config/omarchy/plugins"
    shellConfigProvider: function() { return root.config }
    shellConfigMutator: function(mutator) {
      var next = JSON.parse(JSON.stringify(root.config || {}))
      mutator(next)
      root.config = next
    }
    onPluginsChanged: root.changeCount++
  }

  Timer {
    interval: 100
    running: true
    repeat: false
    onTriggered: root.runChecks()
  }
}
