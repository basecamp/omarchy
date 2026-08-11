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

        var faceIndicator = view.children ? findByObjectName(view, "faceIndicator") : null
        var fingerprintIndicator = view.children ? findByObjectName(view, "fingerprintIndicator") : null
        root.assertTrue(faceIndicator !== null, "face indicator exists in the lock view")
        root.assertTrue(fingerprintIndicator !== null, "fingerprint indicator exists in the lock view")

        if (faceIndicator && fingerprintIndicator) {
          view.faceConfigured = false
          view.fingerprintConfigured = false
          root.assertTrue(!faceIndicator.visible, "face indicator is hidden when face authentication is not configured")
          root.assertTrue(!fingerprintIndicator.visible, "fingerprint indicator is hidden when no sensor is configured")
          root.assertTrue(view.biometricReserve === 0, "no space is reserved when biometrics are not configured")

          view.faceConfigured = true
          root.assertTrue(faceIndicator.visible, "face indicator is shown when face authentication is configured")
          root.assertTrue(!fingerprintIndicator.visible, "fingerprint indicator stays hidden in the face-only layout")
          var faceReserve = view.biometricReserve
          root.assertTrue(faceReserve > faceIndicator.width,
            "face-only layout reserves icon clearance, got reserve " + faceReserve + " vs icon " + faceIndicator.width)

          view.faceConfigured = false
          view.fingerprintConfigured = true
          root.assertTrue(!faceIndicator.visible, "face indicator stays hidden in the fingerprint-only layout")
          root.assertTrue(fingerprintIndicator.visible, "fingerprint indicator is shown when a sensor is configured")
          var fingerprintReserve = view.biometricReserve
          root.assertTrue(fingerprintReserve > fingerprintIndicator.width,
            "fingerprint-only layout reserves icon clearance, got reserve " + fingerprintReserve + " vs icon " + fingerprintIndicator.width)

          view.faceConfigured = true
          root.assertTrue(faceIndicator.visible && fingerprintIndicator.visible,
            "both indicators are shown when both authentication methods are configured")
          root.assertTrue(view.biometricReserve >= Math.max(faceReserve, fingerprintReserve),
            "combined layout reserves enough space for its wider indicator")

          // The shared reserve keeps both sides equal and long passwords clear
          // of both icons even when only one method is configured.
          view.passwordText = "x".repeat(80)
          var clearWidth = view.fieldWidth - 2 * view.biometricReserve
          probe.font.pixelSize = Math.max(1, Math.floor(view.passwordDotFontSize * view.passwordDotScale))
          probe.font.letterSpacing = view.passwordDotLetterSpacing * view.passwordDotScale
          probe.text = "●".repeat(80)
          root.assertTrue(probe.advanceWidth <= clearWidth,
            "80 dots stay clear of both indicators, need " + probe.advanceWidth + "px of " + clearWidth)
        }

        view.destroy()
      } catch (error) {
        root.fail("lock biometric indicators fixture threw: " + error)
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
