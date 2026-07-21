import QtQuick
import Quickshell

ShellRoot {
  id: root

  property string resultPath: Quickshell.env("OMARCHY_QML_TEST_RESULT")
  property var failures: []
  property var commands: []

  function fail(message) {
    failures.push(String(message))
  }

  function assertTrue(condition, message) {
    if (!condition) fail(message)
  }

  QtObject {
    id: notificationService
    property bool doNotDisturb: false
    function setDoNotDisturb(value) {
      doNotDisturb = !!value
    }
  }

  QtObject {
    id: idleService
    property bool stayAwake: false
    readonly property bool idleEnabled: !stayAwake
    function setIdleEnabled(value) {
      stayAwake = !value
    }
  }

  QtObject {
    id: mockShell
    function firstPartyServiceFor(id) {
      if (id === "omarchy.notifications") return notificationService
      if (id === "omarchy.idle") return idleService
      return null
    }
  }

  QtObject {
    id: mockBar
    property bool vertical: false
    property int barSize: 26
    property string fontFamily: "monospace"
    property color barForeground: "white"
    property color urgent: "red"
    property bool foregroundAnimationEnabled: false
    property bool centerSectionRevealHeld: false
    property bool centerHoverRevealSuppressed: false
    property var shell: mockShell
    function run(command) {
      root.commands.push(String(command))
    }
    function showTooltip(target, text) {}
    function hideTooltip(target) {}
    function registerClickTarget(target) {}
    function unregisterClickTarget(target) {}
  }

  QtObject {
    id: indicatorHost
    property bool revealInactiveIndicators: true
  }

  function createIndicator(name) {
    var component = Qt.createComponent("file://" + rootPath + "/shell/plugins/bar/indicators/" + name + ".qml")
    if (component.status !== Component.Ready) {
      fail(name + " failed to load: " + component.errorString())
      return null
    }

    var item = component.createObject(root, {
      indicatorHost: indicatorHost,
      indicatorBlock: "inactive",
      activeOverride: null
    })
    if (!item) {
      fail(name + " failed to instantiate: " + component.errorString())
      return null
    }
    return item
  }

  function injectBar(item) {
    assertTrue(item.bar === null || item.bar === undefined, item.moduleName + " starts without bar")
    item.bar = mockBar
    assertTrue(item.bar === mockBar, item.moduleName + " accepts delayed bar injection")
  }

  function commandCount(command) {
    var count = 0
    for (var i = 0; i < commands.length; i++) {
      if (commands[i] === command) count++
    }
    return count
  }

  function writeResult() {
    var payload = JSON.stringify({
      ok: failures.length === 0,
      failures: failures,
      commands: commands,
      dnd: notificationService.doNotDisturb
    })

    if (resultPath) {
      Quickshell.execDetached(["bash", "-lc", "printf '%s' " + shellQuote(payload) + " > " + shellQuote(resultPath)])
    }
  }

  function checkIndicatorTray() {
    idleService.setIdleEnabled(true)

    var component = Qt.createComponent("file://" + rootPath + "/shell/plugins/bar/widgets/Indicators.qml")
    if (component.status !== Component.Ready) {
      fail("Indicators failed to load: " + component.errorString())
      writeResult()
      return
    }

    var tray = component.createObject(root, {
      bar: mockBar,
      settings: { items: ["StayAwake"] }
    })
    if (!tray) {
      fail("Indicators failed to instantiate: " + component.errorString())
      writeResult()
      return
    }

    Qt.callLater(function() {
      root.assertTrue(tray.implicitWidth === 0, "inactive indicator tray starts collapsed")
      mockBar.centerSectionRevealHeld = true

      Qt.callLater(function() {
        root.assertTrue(tray.implicitWidth > 0, "inactive indicator tray expands on center hover")
        mockBar.centerSectionRevealHeld = false

        Qt.callLater(function() {
          root.assertTrue(tray.implicitWidth === 0, "inactive indicator tray collapses after hover")
          tray.destroy()
          root.writeResult()
        })
      })
    })
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  readonly property string rootPath: Quickshell.env("OMARCHY_PATH")

  Timer {
    interval: 1
    running: true
    repeat: false
    onTriggered: {
      var dnd = root.createIndicator("Dnd")
      if (dnd) {
        dnd.moduleName = "Dnd"
        root.injectBar(dnd)
        notificationService.doNotDisturb = false
        dnd.triggerPress(Qt.LeftButton)
        root.assertTrue(notificationService.doNotDisturb === true, "DND left click toggles notification service")
      }

      var nightLight = root.createIndicator("NightLight")
      if (nightLight) {
        nightLight.moduleName = "NightLight"
        root.injectBar(nightLight)
        nightLight.triggerPress(Qt.LeftButton)
        root.assertTrue(root.commandCount("omarchy-toggle-nightlight") === 1, "Night Light left click runs toggle command")
      }

      var screenRecording = root.createIndicator("ScreenRecording")
      if (screenRecording) {
        screenRecording.moduleName = "ScreenRecording"
        root.injectBar(screenRecording)
        screenRecording.triggerPress(Qt.LeftButton)
        root.assertTrue(root.commandCount("omarchy-menu toggle trigger.capture.screenrecord") === 1, "Screen Recording left click opens capture menu when idle")
        screenRecording.recording = true
        screenRecording.triggerPress(Qt.LeftButton)
        root.assertTrue(root.commandCount("omarchy-capture-screenrecording --stop-recording") === 1, "Screen Recording left click stops active recording")
      }

      var dictation = root.createIndicator("Dictation")
      if (dictation) {
        dictation.moduleName = "Dictation"
        root.injectBar(dictation)
        dictation.triggerPress(Qt.LeftButton)
        dictation.triggerPress(Qt.RightButton)
        root.assertTrue(root.commandCount("omarchy-voxtype-config") === 2, "Dictation clicks run config command")
        root.assertTrue(root.commandCount("omarchy-voxtype-model") === 0, "Dictation clicks do not run model command")
      }

      var stayAwake = root.createIndicator("StayAwake")
      if (stayAwake) {
        stayAwake.moduleName = "StayAwake"
        root.injectBar(stayAwake)
        stayAwake.triggerPress(Qt.LeftButton)
        root.assertTrue(idleService.stayAwake === true, "Stay Awake left click toggles the idle service")
      }

      root.checkIndicatorTray()
    }
  }
}
