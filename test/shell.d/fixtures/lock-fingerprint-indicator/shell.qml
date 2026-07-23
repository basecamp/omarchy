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

        var indicator = view.children ? findByObjectName(view, "fingerprintIndicator") : null
        root.assertTrue(indicator !== null, "fingerprint indicator exists in the lock view")

        if (indicator) {
          view.fingerprintConfigured = false
          root.assertTrue(!indicator.visible, "fingerprint indicator is hidden when no sensor is configured")

          view.fingerprintConfigured = true
          root.assertTrue(indicator.visible, "fingerprint indicator is shown when a sensor is configured")

          // The field reserves space for the icon so a long password can never
          // slide underneath it. The reserve must exceed the icon's own width
          // (leaving a gap), and the shrunk dots must fit the reserved-clear
          // area even at extreme lengths.
          root.assertTrue(view.fingerprintReserve > indicator.width,
            "reserved space exceeds the icon width, got reserve " + view.fingerprintReserve + " vs icon " + indicator.width)

          view.passwordText = "x".repeat(80)
          var clearWidth = view.fieldWidth - 2 * view.fingerprintReserve
          probe.font.pixelSize = Math.max(1, Math.floor(view.passwordDotFontSize * view.passwordDotScale))
          probe.font.letterSpacing = view.passwordDotLetterSpacing * view.passwordDotScale
          probe.text = "●".repeat(80)
          root.assertTrue(probe.advanceWidth <= clearWidth,
            "80 dots stay clear of the fingerprint icon, need " + probe.advanceWidth + "px of " + clearWidth)

          view.fingerprintConfigured = false
          root.assertTrue(view.fingerprintReserve === 0, "no space is reserved when no sensor is configured")
        }

        view.destroy()
      } catch (error) {
        root.fail("lock fingerprint indicator fixture threw: " + error)
      } finally {
        root.writeResult()
      }
    }
  }

  function findByObjectName(node, name) {
    if (!node) return null
    if (node.objectName === name) return node
    var kids = node.children || []
    for (var i = 0; i < kids.length; i++) {
      var found = findByObjectName(kids[i], name)
      if (found) return found
    }
    return null
  }
}
