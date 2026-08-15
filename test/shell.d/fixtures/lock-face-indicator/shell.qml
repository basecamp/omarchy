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

        var face = findByObjectName(view, "faceIndicator")
        var fingerprint = findByObjectName(view, "fingerprintIndicator")
        var input = findByObjectName(view, "passwordInput")
        root.assertTrue(face !== null, "face indicator exists in the lock view")
        root.assertTrue(fingerprint !== null, "fingerprint indicator exists in the lock view")
        root.assertTrue(input !== null, "password input exists in the lock view")

        if (face && fingerprint && input) {
          view.fingerprintConfigured = false
          view.faceConfigured = false
          root.assertTrue(!face.visible, "face indicator is hidden when no face model is enrolled")
          root.assertTrue(view.fingerprintReserve === 0, "no space is reserved when nothing biometric is configured")

          view.faceConfigured = true
          root.assertTrue(face.visible, "face indicator is shown when a face model is enrolled")
          root.assertTrue(view.fingerprintReserve > face.width,
            "reserved space exceeds the face icon width, got reserve " + view.fingerprintReserve + " vs icon " + face.width)

          // Face alone sits where the fingerprint icon would: pinned inside the
          // field's right edge, not floating mid-field.
          var faceRightAlone = face.mapToItem(view, face.width, 0).x
          root.assertTrue(faceRightAlone > view.width / 2,
            "face icon alone sits in the right half of the field, got right edge " + faceRightAlone)

          // With both enrolled the icons share the right edge without overlapping
          // and the reserve covers the pair.
          view.fingerprintConfigured = true
          var faceRight = face.mapToItem(view, face.width, 0).x
          var fingerprintLeft = fingerprint.mapToItem(view, 0, 0).x
          root.assertTrue(faceRight <= fingerprintLeft,
            "face icon sits left of the fingerprint icon, got face right " + faceRight + " vs fingerprint left " + fingerprintLeft)
          root.assertTrue(view.fingerprintReserve > face.width + fingerprint.width,
            "reserved space covers both icons, got reserve " + view.fingerprintReserve + " vs icons " + (face.width + fingerprint.width))

          view.passwordText = "x".repeat(80)
          var clearWidth = view.fieldWidth - 2 * view.fingerprintReserve
          probe.font.pixelSize = Math.max(1, Math.floor(view.passwordDotFontSize * view.passwordDotScale))
          probe.font.letterSpacing = view.passwordDotLetterSpacing * view.passwordDotScale
          probe.text = "\u25CF".repeat(80)
          root.assertTrue(probe.advanceWidth <= clearWidth,
            "80 dots stay clear of both icons, need " + probe.advanceWidth + "px of " + clearWidth)
          view.passwordText = ""

          // A bare Enter asks for a face scan, but only once a model is enrolled;
          // a typed password never does.
          var faceSubmits = 0
          var passwordSubmits = 0
          view.submitFace.connect(function() { faceSubmits += 1 })
          view.submitPassword.connect(function() { passwordSubmits += 1 })

          view.faceConfigured = false
          input.accepted()
          root.assertTrue(faceSubmits === 0, "empty Enter does not request a face scan when none is enrolled")

          view.faceConfigured = true
          input.accepted()
          root.assertTrue(faceSubmits === 1, "empty Enter requests a face scan when a model is enrolled, got " + faceSubmits)

          view.passwordText = "secret"
          input.accepted()
          root.assertTrue(faceSubmits === 1 && passwordSubmits === 1,
            "a typed password submits as password, not face, got face " + faceSubmits + " password " + passwordSubmits)
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
