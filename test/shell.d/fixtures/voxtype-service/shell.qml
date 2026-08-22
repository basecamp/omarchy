import QtQuick
import Quickshell

ShellRoot {
  id: root

  readonly property string resultPath: Quickshell.env("OMARCHY_QML_TEST_RESULT")
  readonly property string rootPath: Quickshell.env("OMARCHY_PATH")
  property var service: null
  property var failures: []
  property var states: []
  property real maxLevel: 0
  property bool levelsReset: false
  property bool resultWritten: false

  function fail(message) {
    failures.push(String(message))
  }

  function assertTrue(condition, message) {
    if (!condition) fail(message)
  }

  function allLevelsReset() {
    if (!service || service.levels.length !== service.levelSlots) return false
    for (var i = 0; i < service.levels.length; i++) {
      if (service.levels[i] !== 0) return false
    }
    return true
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function writeResult() {
    if (resultWritten) return
    resultWritten = true

    assertTrue(states.join(",") === "recording,idle,transcribing", "status stream ignores malformed input and recovers")
    assertTrue(maxLevel >= 0.79, "audio JSON accumulates peak levels")
    assertTrue(levelsReset, "levels reset when capture ends")
    assertTrue(service && service.transcribing && service.busy, "transcribing state remains busy")

    var payload = JSON.stringify({
      ok: failures.length === 0,
      failures: failures,
      states: states,
      maxLevel: maxLevel,
      levelsReset: levelsReset
    })
    Quickshell.execDetached(["bash", "-lc", "printf '%s' " + shellQuote(payload) + " > " + shellQuote(resultPath)])
  }

  Item { id: host }

  Connections {
    target: root.service

    function onStateChanged() {
      root.states.push(root.service.state)
      if (root.service.state === "idle" && root.states.indexOf("recording") !== -1) resetCheck.restart()
      if (root.service.state === "transcribing") finishCheck.restart()
    }

    function onLevelsChanged() {
      for (var i = 0; i < root.service.levels.length; i++) {
        root.maxLevel = Math.max(root.maxLevel, root.service.levels[i])
      }
    }
  }

  Timer {
    id: resetCheck
    interval: 1
    onTriggered: root.levelsReset = root.allLevelsReset()
  }

  Timer {
    id: finishCheck
    interval: 100
    onTriggered: root.writeResult()
  }

  Timer {
    interval: 6000
    running: true
    onTriggered: {
      root.fail("Voxtype service test timed out")
      root.writeResult()
    }
  }

  Component.onCompleted: {
    var component = Qt.createComponent("file://" + rootPath + "/shell/plugins/services/voxtype/Service.qml", Component.PreferSynchronous)
    if (component.status !== Component.Ready) {
      fail("Voxtype service failed to load: " + component.errorString())
      writeResult()
      return
    }

    service = component.createObject(host)
    if (!service) {
      fail("Voxtype service failed to instantiate: " + component.errorString())
      writeResult()
    }
  }
}
