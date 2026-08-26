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

        var indicator = view.children ? findByObjectName(view, "faceIndicator") : null
        root.assertTrue(indicator !== null, "face indicator exists in the lock view")

        if (indicator) {
          view.faceConfigured = false
          root.assertTrue(!indicator.visible, "face indicator is hidden when face auth is not configured")

          view.faceConfigured = true
          root.assertTrue(indicator.visible, "face indicator is shown when face auth is configured")

          // The field reserves space for the icon so a long password can never
          // slide underneath it, whichever biometric icons are shown.
          root.assertTrue(view.iconReserve > indicator.width,
            "reserved space exceeds the icon width, got reserve " + view.iconReserve + " vs icon " + indicator.width)

          view.passwordText = "x".repeat(80)
          var clearWidth = view.fieldWidth - 2 * view.iconReserve
          probe.font.pixelSize = Math.max(1, Math.floor(view.passwordDotFontSize * view.passwordDotScale))
          probe.font.letterSpacing = view.passwordDotLetterSpacing * view.passwordDotScale
          probe.text = "●".repeat(80)
          root.assertTrue(probe.advanceWidth <= clearWidth,
            "80 dots stay clear of the face icon, need " + probe.advanceWidth + "px of " + clearWidth)

          // Both biometric icons shown together share one symmetric reserve.
          view.fingerprintConfigured = true
          root.assertTrue(view.iconReserve > 0, "space stays reserved with both icons shown")
          view.fingerprintConfigured = false

          view.faceConfigured = false
          root.assertTrue(view.iconReserve === 0, "no space is reserved when nothing is configured")
        }

        view.destroy()
      } catch (error) {
        root.fail("lock face indicator fixture threw: " + error)
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
