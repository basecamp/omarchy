import QtQuick
import Quickshell
import qs.Commons

ShellRoot {
  id: root

  readonly property string resultPath: Quickshell.env("OMARCHY_QML_TEST_RESULT")
  readonly property string rootPath: Quickshell.env("OMARCHY_PATH")
  property var failures: []

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
      failures: failures
    })

    if (resultPath) {
      Quickshell.execDetached(["bash", "-lc", "printf '%s' " + shellQuote(payload) + " > " + shellQuote(resultPath)])
    }
  }

  Item { id: host; width: 800; height: 600 }

  TextMetrics {
    id: probe
    font.family: Style.font.family
  }

  Timer {
    interval: 1
    running: true
    repeat: false
    onTriggered: {
      try {
        var component = Qt.createComponent("file://" + root.rootPath + "/shell/plugins/lock/LockView.qml", Component.PreferSynchronous)
        if (component.status !== Component.Ready) {
          root.fail("LockView failed to load: " + component.errorString())
          return
        }

        var view = component.createObject(host, { width: 800, height: 600, loadBackground: false })
        if (!view) {
          root.fail("LockView failed to instantiate: " + component.errorString())
          return
        }

        view.passwordText = "x".repeat(6)
        root.assertTrue(view.passwordDotScale === 1, "short passwords keep full-size dots, got scale " + view.passwordDotScale)

        view.passwordText = "x".repeat(40)
        var longScale = view.passwordDotScale
        root.assertTrue(longScale > 0 && longScale < 1, "overflowing passwords shrink the dots, got scale " + longScale)

        view.passwordText = "x".repeat(80)
        var longerScale = view.passwordDotScale
        root.assertTrue(longerScale < longScale, "dots keep shrinking as the password grows, got " + longerScale + " vs " + longScale)

        probe.font.pixelSize = Math.max(1, Math.floor(view.passwordDotFontSize * longerScale))
        probe.font.letterSpacing = view.passwordDotLetterSpacing * longerScale
        probe.text = "●".repeat(80)
        root.assertTrue(probe.advanceWidth <= view.fieldWidth, "all 80 dots fit inside the field, need " + probe.advanceWidth + "px of " + view.fieldWidth)

        view.destroy()
      } catch (error) {
        root.fail("lock password overflow fixture threw: " + error)
      } finally {
        root.writeResult()
      }
    }
  }
}
