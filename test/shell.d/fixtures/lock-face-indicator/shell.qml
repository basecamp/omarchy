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
        var finger = findByObjectName(view, "fingerprintIndicator")
        root.assertTrue(face !== null, "face indicator exists in the lock view")

        if (face && finger) {
          view.faceConfigured = false
          root.assertTrue(!face.visible, "face indicator is hidden when no camera is configured")
          root.assertTrue(view.faceReserve === 0, "no space is reserved when no camera is configured")

          view.faceConfigured = true
          root.assertTrue(face.visible, "face indicator is shown when a camera is configured")
          root.assertTrue(view.faceReserve > face.width,
            "reserved space exceeds the icon width, got reserve " + view.faceReserve + " vs icon " + face.width)

          // One hint per edge: stacking them on the same side would overlap.
          view.fingerprintConfigured = true
          root.assertTrue(face.x < finger.x, "the face hint sits on the opposite edge from the fingerprint")

          // The dots are centered, so the clear margin is symmetric and has to
          // satisfy whichever icon is wider.
          root.assertTrue(view.indicatorReserve === Math.max(view.faceReserve, view.fingerprintReserve),
            "the reserve covers the wider of the two hints")

          view.passwordText = "x".repeat(80)
          var clearWidth = view.fieldWidth - 2 * view.indicatorReserve
          probe.font.pixelSize = Math.max(1, Math.floor(view.passwordDotFontSize * view.passwordDotScale))
          probe.font.letterSpacing = view.passwordDotLetterSpacing * view.passwordDotScale
          probe.text = "●".repeat(80)
          root.assertTrue(probe.advanceWidth <= clearWidth,
            "80 dots stay clear of both hints, need " + probe.advanceWidth + "px of " + clearWidth)
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
