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

        var toggle = findByObjectName(view, "passwordRevealMouseArea")
        root.assertTrue(toggle !== null, "reveal toggle mouse area exists in the lock view")

        // Empty-field no-op: neither entry point can arm a reveal with
        // nothing typed yet.
        root.assertTrue(!view.passwordRevealed, "starts hidden")
        root.assertTrue(toggle && !toggle.enabled, "reveal toggle is disabled while the field is empty")
        view.toggleReveal()
        root.assertTrue(!view.passwordRevealed, "toggling on an empty field is a no-op, mirroring the disabled mouse button")

        // Both toggle paths (the mouse handler and the Ctrl+Space shortcut)
        // call the same root.toggleReveal(), so exercising it here covers
        // both call sites' shared logic.
        view.passwordText = "hunter2"
        root.assertTrue(toggle && toggle.enabled, "reveal toggle is enabled once there is text")
        view.toggleReveal()
        root.assertTrue(view.passwordRevealed, "toggling with text present reveals the password")
        view.toggleReveal()
        root.assertTrue(!view.passwordRevealed, "toggling again re-hides the password")

        // Reset on clear/submit: both the clear shortcuts (Escape, Ctrl+U)
        // and a submit funnel through passwordTextEdited("") externally,
        // which round-trips back into passwordText -- exactly what this
        // reproduces directly.
        view.toggleReveal()
        root.assertTrue(view.passwordRevealed, "revealed before the field is cleared")
        view.passwordText = ""
        root.assertTrue(!view.passwordRevealed, "clearing the field resets reveal state, so the next attempt starts masked")

        // Revealed-text overflow: a long revealed password must still be
        // clamped to fit the field, the same guarantee already covered for
        // masked dots by the lock-password-overflow test.
        view.passwordText = "x".repeat(80)
        view.passwordRevealed = true
        probe.font.pixelSize = Math.max(1, Math.floor(view.fieldFontSize * view.revealedTextScale))
        probe.font.letterSpacing = 0
        probe.text = view.passwordText
        root.assertTrue(probe.advanceWidth <= view.fieldWidth,
          "revealed text fits inside the field, need " + probe.advanceWidth + "px of " + view.fieldWidth)
        root.assertTrue(view.revealedTextScale < 1, "an 80-char revealed password shrinks to fit, got scale " + view.revealedTextScale)

        view.destroy()
      } catch (error) {
        root.fail("lock password reveal fixture threw: " + error)
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
