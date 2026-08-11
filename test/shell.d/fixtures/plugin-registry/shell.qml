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

  function manifest(id, kinds, entryPoints, barWidget) {
    var value = {
      schemaVersion: 1,
      id: id,
      name: id,
      version: "1.0.0",
      kinds: kinds,
      entryPoints: entryPoints
    }
    if (barWidget) value.barWidget = barWidget
    return value
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
    scan += block("firstparty", "/first/hybrid", manifest("omarchy.hybrid", ["menu", "bar-widget"], { menu: "Menu.qml", barWidget: "Widget.qml" }))
    scan += block("thirdparty", "/third/panel", manifest("third.panel", ["panel"], { panel: "Panel.qml" }))
    scan += block("thirdparty", "/third/widget", manifest("third.widget", ["bar-widget"], { barWidget: "Widget.qml" }, { defaultSection: "left" }))
    scan += block("thirdparty", "/third/center-widget", manifest("third.center-widget", ["bar-widget"], { barWidget: "Widget.qml" }))
    scan += block("thirdparty", "/third/right-widget", manifest("third.right-widget", ["bar-widget"], { barWidget: "Widget.qml" }, { defaultSection: "right" }))
    var localWidget = manifest("local.first-widget", ["bar-widget"], { barWidget: "Widget.qml" })
    localWidget.omarchy = { clonedFrom: "omarchy.first-widget" }
    scan += block("thirdparty", "/third/local-widget", localWidget)
    var localWeather = manifest("local.weather", ["bar-widget"], { barWidget: "Widget.qml" })
    localWeather.omarchy = { clonedFrom: "omarchy.weather" }
    scan += block("thirdparty", "/third/local-weather", localWeather)
    var localHybrid = manifest("local.hybrid", ["menu", "bar-widget"], { menu: "Menu.qml", barWidget: "Widget.qml" })
    localHybrid.omarchy = { clonedFrom: "omarchy.hybrid" }
    scan += block("thirdparty", "/third/local-hybrid", localHybrid)
    var localPanel = manifest("local.grouped-panel", ["panel"], { panel: "Panel.qml" })
    localPanel.omarchy = { clonedFrom: "omarchy.grouped-panel" }
    scan += block("thirdparty", "/third/local-panel", localPanel)
    var localBar = manifest("local.bar", ["bar"], { bar: "Bar.qml" })
    localBar.omarchy = { clonedFrom: "omarchy.bar" }
    scan += block("thirdparty", "/third/local-bar", localBar)
    scan += block("thirdparty", "/third/bar", manifest("third.bar", ["bar"], { bar: "Bar.qml" }))
    scan += block("thirdparty", "/third/shadow", manifest("omarchy.first-widget", ["panel"], { panel: "Panel.qml" }))
    scan += block("thirdparty", "/third/reserved", manifest("omarchy.reserved", ["panel"], { panel: "Panel.qml" }))
    scan += block("thirdparty", "/third/unsafe", manifest("third.unsafe", ["panel"], { panel: "../Panel.qml" }))
    scan += block("thirdparty", "/third/missing", { schemaVersion: 1, id: "third.missing", name: "missing", version: "1.0.0", kinds: ["panel"] })
    scan += block("thirdparty", "/third/bad-section", manifest("third.bad-section", ["bar-widget"], { barWidget: "Widget.qml" }, { defaultSection: "bottom" }))
    scan += block("thirdparty", "/third/schema", { schemaVersion: 2, id: "third.schema", name: "schema", version: "1.0.0", kinds: ["panel"], entryPoints: { panel: "Panel.qml" } })
    scan += block("thirdparty", "/third/bad-json", "{")

    registry.parseScanOutput(scan)

    root.assertDeepEqual(pluginIds(), [
      "local.bar",
      "local.first-widget",
      "local.grouped-panel",
      "local.hybrid",
      "local.weather",
      "omarchy.bar",
      "omarchy.first-widget",
      "omarchy.grouped-panel",
      "omarchy.hybrid",
      "third.bar",
      "third.center-widget",
      "third.panel",
      "third.right-widget",
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
    root.assertTrue(!has("third.bad-section"), "invalid default bar widget sections are rejected")
    root.assertTrue(!has("third.schema"), "unsupported schema versions are rejected")

    root.assertTrue(registry.isEnabled("omarchy.first-widget"), "first-party plugins are implicitly enabled")
    root.assertTrue(registry.isEnabled("omarchy.bar"), "built-in bar option is active by default")
    root.assertTrue(!registry.isEnabled("third.bar"), "third-party bar options start inactive")
    root.assertTrue(!registry.isEnabled("third.panel"), "third-party plugins start disabled")
    root.assertEqual(registry.resolveEnabledId("omarchy.first-widget"), "omarchy.first-widget", "inactive clones do not replace their source id")

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
    root.assertDeepEqual(root.config.bar.layout.left, [{ id: "third.widget" }], "enabling bar widgets uses their default section")
    root.assertTrue(registry.isEnabled("third.widget"), "enabled bar widgets are found")
    registry.setEnabled("third.widget", false)
    root.assertDeepEqual(root.config.bar.layout.left, [], "disabling bar widgets removes layout entry")

    root.config = {
      version: 1,
      bar: {
        layout: {
          left: [{ id: "omarchy.workspaces" }, { id: "omarchy.menu" }],
          center: [{ id: "omarchy.weather" }, { id: "omarchy.clock" }],
          right: [{ id: "omarchy.tray" }]
        }
      },
      plugins: []
    }
    registry.setEnabled("third.widget", true)
    root.assertDeepEqual(
      root.config.bar.layout.left,
      [{ id: "omarchy.workspaces" }, { id: "third.widget" }, { id: "omarchy.menu" }],
      "enabling a widget inserts it after its section anchor"
    )
    registry.setEnabled("third.center-widget", true)
    root.assertDeepEqual(
      root.config.bar.layout.center,
      [{ id: "omarchy.weather" }, { id: "third.center-widget" }, { id: "omarchy.clock" }],
      "widgets without a default section use the center anchor"
    )
    registry.setEnabled("third.right-widget", true)
    root.assertDeepEqual(
      root.config.bar.layout.right,
      [{ id: "omarchy.tray" }, { id: "third.right-widget" }],
      "right widgets use the right anchor"
    )

    root.config = { version: 1, bar: { layout: { left: [], center: [], right: [] } }, plugins: [] }
    registry.setEnabled("third.right-widget", true)
    root.assertDeepEqual(root.config.bar.layout.right, [{ id: "third.right-widget" }], "widgets append when their section anchor is absent")

    root.config = {
      version: 1,
      bar: { layout: { left: [{ id: "third.widget", size: 3 }], center: [], right: [] } },
      plugins: []
    }
    root.assertEqual(registry.moveBarWidget("third.widget", { section: "right" }), "", "registry moves widgets")
    root.assertDeepEqual(root.config.bar.layout.right, [{ id: "third.widget", size: 3 }], "registry move preserves widget settings")
    root.assertEqual(registry.setBarWidget("third.widget", "size", 7, {}), "", "registry sets widget options")
    root.assertEqual(root.config.bar.layout.right[0].size, 7, "registry persists widget options")

    root.config = { version: 1, bar: { layout: { left: [], center: [], right: [] } }, plugins: [] }
    registry.setEnabled("third.widget", true, { section: "right", index: 0 })
    root.assertDeepEqual(root.config.bar.layout.right, [{ id: "third.widget" }], "enabling with placement is one registry transition")

    // A bar the placement's neighbour is not on still gets the widget.
    root.config = {
      version: 1,
      bar: { layout: { left: [], center: [{ id: "omarchy.weather" }], right: [] } },
      plugins: []
    }
    root.assertTrue(
      !registry.setEnabled("third.center-widget", true, { after: "omarchy.first-widget" }),
      "enabling against a widget the bar does not carry is refused"
    )
    root.assertEqual(
      registry.lastEnableError,
      "could not find target widget omarchy.first-widget",
      "a refused enable names the target it could not find"
    )
    root.assertDeepEqual(root.config.bar.layout.center, [{ id: "omarchy.weather" }], "a refused enable places nothing")
    root.assertEqual(
      registry.putBarWidget("third.center-widget", { after: "omarchy.first-widget" }),
      "",
      "put accepts a placement target the bar does not carry"
    )
    root.assertDeepEqual(
      root.config.bar.layout.center,
      [{ id: "omarchy.weather" }, { id: "third.center-widget" }],
      "put falls back to the section anchor when its target is missing"
    )

    // The anchor sits after the clone, so a fallback would land elsewhere.
    root.config = {
      version: 1,
      bar: { layout: { left: [], center: [{ id: "local.first-widget" }, { id: "omarchy.weather" }], right: [] } },
      plugins: []
    }
    root.assertEqual(
      registry.putBarWidget("third.center-widget", { after: "omarchy.first-widget" }),
      "",
      "put places against a target that has been cloned"
    )
    root.assertDeepEqual(
      root.config.bar.layout.center,
      [{ id: "local.first-widget" }, { id: "third.center-widget" }, { id: "omarchy.weather" }],
      "a clone stands in for the widget it was cloned from as a placement target"
    )

    // The anchor a fallback lands against is as clonable as the target.
    root.config = {
      version: 1,
      bar: { layout: { left: [], center: [{ id: "local.weather" }, { id: "omarchy.clock" }], right: [] } },
      plugins: []
    }
    root.assertEqual(
      registry.putBarWidget("third.center-widget", { after: "omarchy.first-widget" }),
      "",
      "put falls back past a cloned anchor"
    )
    root.assertDeepEqual(
      root.config.bar.layout.center,
      [{ id: "local.weather" }, { id: "third.center-widget" }, { id: "omarchy.clock" }],
      "a cloned anchor still anchors the section it was cloned into"
    )

    root.config = {
      version: 1,
      bar: { layout: { left: [{ id: "third.center-widget", size: 2 }], center: [], right: [] } },
      plugins: []
    }
    root.assertEqual(registry.putBarWidget("third.center-widget", { section: "right" }), "", "put accepts a widget that is already on the bar")
    root.assertDeepEqual(
      root.config.bar.layout.left,
      [{ id: "third.center-widget", size: 2 }],
      "put leaves a widget that is already on the bar where its owner put it"
    )
    root.assertDeepEqual(root.config.bar.layout.right, [], "put adds no second entry for a widget already on the bar")
    root.assertEqual(registry.putBarWidget("third.absent", {}), "unknown", "put reports a widget it does not know")

    root.config = {
      version: 1,
      bar: { layout: { left: [], center: [{ id: "local.first-widget", size: 5 }], right: [] } },
      plugins: []
    }
    root.assertEqual(registry.putBarWidget("omarchy.first-widget", {}), "", "put accepts a widget whose clone is on the bar")
    root.assertDeepEqual(
      root.config.bar.layout.center,
      [{ id: "local.first-widget", size: 5 }],
      "put leaves a clone of the widget it was asked to place alone"
    )

    // Refusing an id the scan has not reached would fail the migration.
    root.config = { version: 1, bar: { layout: { left: [], center: [], right: [] } }, plugins: [] }
    registry.scanning = true
    root.assertEqual(registry.putBarWidget("third.absent", {}), "not ready", "put waits for a scan that has not reached its widget")
    root.assertDeepEqual(root.config.bar.layout.center, [], "put places nothing while it is still waiting")
    root.assertEqual(registry.putBarWidget("third.center-widget", {}), "", "put places a widget the scan has already read")
    registry.scanning = false

    root.config = {
      version: 1,
      bar: { layout: { left: [], center: [{ id: "omarchy.first-widget", size: 4 }], right: [] } },
      plugins: []
    }
    registry.setEnabled("local.first-widget", true)
    root.assertDeepEqual(
      root.config.bar.layout.center,
      [{ id: "local.first-widget", size: 4 }],
      "enabling a widget clone replaces its source in place"
    )
    root.assertEqual(registry.resolveEnabledId("omarchy.first-widget"), "local.first-widget", "enabled clones receive calls made to their source id")
    registry.setEnabled("omarchy.first-widget", true)
    root.assertDeepEqual(
      root.config.bar.layout.center,
      [{ id: "omarchy.first-widget", size: 4 }],
      "enabling a clone source switches back without duplicates"
    )
    registry.setEnabled("local.first-widget", true)
    registry.setEnabled("local.first-widget", false)
    root.assertDeepEqual(
      root.config.bar.layout.center,
      [{ id: "omarchy.first-widget", size: 4 }],
      "disabling a widget clone restores its source in place"
    )

    root.config = {
      version: 1,
      bar: { layout: { left: [], center: ["omarchy.first-widget"], right: [] } },
      plugins: []
    }
    registry.setEnabled("local.first-widget", true)
    root.assertDeepEqual(root.config.bar.layout.center, [{ id: "local.first-widget" }], "clone replacement normalizes string entries")
    registry.setEnabled("local.first-widget", false)
    root.assertDeepEqual(root.config.bar.layout.center, [{ id: "omarchy.first-widget" }], "clone restoration normalizes string entries")

    root.config = {
      version: 1,
      bar: { layout: { left: [{ id: "omarchy.hybrid" }], center: [], right: [] } },
      plugins: []
    }
    registry.setEnabled("local.hybrid", true)
    root.assertDeepEqual(root.config.bar.layout.left, [{ id: "local.hybrid" }], "enabling a multi-kind clone replaces its widget")
    root.assertDeepEqual(root.config.disabledPlugins, ["omarchy.hybrid"], "enabling a multi-kind clone disables the source")
    registry.setEnabled("local.hybrid", false)
    root.assertDeepEqual(root.config.bar.layout.left, [{ id: "omarchy.hybrid" }], "disabling a multi-kind clone restores its widget")
    root.assertTrue(root.config.disabledPlugins === undefined, "disabling a multi-kind clone enables the source")

    root.config = { version: 1, bar: { layout: { left: [], center: [], right: [] } }, plugins: [] }
    registry.setEnabled("local.grouped-panel", true)
    root.assertDeepEqual(root.config.plugins, [{ id: "local.grouped-panel" }], "enabling an ordinary clone adds it")
    root.assertDeepEqual(root.config.disabledPlugins, ["omarchy.grouped-panel"], "enabling an ordinary clone disables the source")
    registry.setEnabled("local.grouped-panel", false)
    root.assertDeepEqual(root.config.plugins, [], "disabling an ordinary clone removes it")
    root.assertTrue(root.config.disabledPlugins === undefined, "disabling an ordinary clone restores the source")

    root.config = {
      version: 1,
      bar: { layout: { left: [], center: [], right: [] } },
      plugins: [],
      disabledPlugins: ["omarchy.grouped-panel"]
    }
    registry.setEnabled("local.grouped-panel", true)
    root.assertDeepEqual(root.config.disabledPlugins, ["omarchy.grouped-panel"], "cloning an already-disabled source keeps it disabled")
    root.assertTrue(root.config.cloneSourceRestores === undefined, "an already-disabled source is not marked for restoration")
    registry.setEnabled("local.grouped-panel", false)
    root.assertDeepEqual(root.config.disabledPlugins, ["omarchy.grouped-panel"], "disabling the clone preserves the source's prior disabled state")

    registry.setEnabled("local.bar", true)
    root.assertEqual(root.config.bar.id, "local.bar", "enabling a cloned bar selects it")
    registry.setEnabled("local.bar", false)
    root.assertTrue(root.config.bar.id === undefined, "disabling a cloned built-in bar restores it")

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

    // A built-in loads by default, so switching one off is recorded the other
    // way round and has to survive round-tripping back on.
    root.config = { version: 1, bar: { layout: { left: [], center: [], right: [] } }, plugins: [] }
    registry.setEnabled("omarchy.grouped-panel", false)
    root.assertDeepEqual(root.config.disabledPlugins, ["omarchy.grouped-panel"], "disabling a first-party plugin records it")
    root.assertTrue(!registry.isEnabled("omarchy.grouped-panel"), "a recorded first-party plugin is disabled")
    root.assertDeepEqual(root.config.plugins, [], "disabling a first-party plugin leaves the plugins array alone")
    registry.setEnabled("omarchy.grouped-panel", true)
    root.assertTrue(root.config.disabledPlugins === undefined, "re-enabling drops the disabled record entirely")
    root.assertTrue(registry.isEnabled("omarchy.grouped-panel"), "a first-party plugin returns to enabled")
    root.assertDeepEqual(root.config.plugins, [], "re-enabling a first-party plugin adds no redundant entry")

    // A widget's place in the bar is its on/off switch. Loadability must not
    // follow it down, or a plugin that is both widget and menu (omarchy.menu)
    // would be locked out of the shell by taking its button off the bar.
    root.config = {
      version: 1,
      bar: { layout: { left: [], center: [], right: [{ id: "omarchy.first-widget" }] } },
      plugins: []
    }
    root.assertTrue(registry.inBar("omarchy.first-widget"), "inBar sees a widget in the layout")
    registry.setEnabled("omarchy.first-widget", false)
    root.assertDeepEqual(root.config.bar.layout.right, [], "disabling a first-party widget removes its layout entry")
    root.assertTrue(root.config.disabledPlugins === undefined, "disabling a first-party widget records nothing else")
    root.assertTrue(!registry.inBar("omarchy.first-widget"), "inBar follows the widget out of the layout")
    root.assertTrue(registry.isEnabled("omarchy.first-widget"), "a first-party widget stays loadable off the bar")
    registry.setEnabled("omarchy.first-widget", true)
    root.assertDeepEqual(root.config.bar.layout.center, [{ id: "omarchy.first-widget" }], "a widget without a default section falls back to center")

    root.config = {
      version: 1,
      bar: { layout: { left: [{ id: "omarchy.hybrid" }], center: [], right: [] } },
      plugins: []
    }
    registry.setEnabled("omarchy.hybrid", false)
    root.assertDeepEqual(root.config.bar.layout.left, [], "disabling a multi-kind built-in removes its widget")
    root.assertTrue(root.config.disabledPlugins === undefined, "disabling a multi-kind widget records nothing else")
    root.assertTrue(registry.isEnabled("omarchy.hybrid"), "a multi-kind built-in remains loadable without its widget")

    var cloneBase = registry.pluginsDir + "/dhh.clock"
    root.assertEqual(registry.localPluginIdForPath(cloneBase + "/BarWidget.qml"), "dhh.clock", "personal clone changes are watched")
    root.assertEqual(registry.localPluginIdForPath(registry.pluginsDir + "/acme.clock/BarWidget.qml"), "acme.clock", "installed plugin changes are watched")
    root.assertEqual(registry.localPluginIdForPath(cloneBase + "/.git/index"), "", "plugin git metadata is ignored")
    root.assertEqual(registry.localPluginIdForPath(registry.pluginsDir + "/.clone.abc123/manifest.json"), "", "hidden staging and backup dirs are ignored")

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
