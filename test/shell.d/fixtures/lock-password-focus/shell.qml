import QtQuick
import QtQuick.Window
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

  function findByObjectName(item, name) {
    if (!item) return null
    if (item.objectName === name) return item

    var children = item.children || []
    for (var i = 0; i < children.length; i++) {
      var found = findByObjectName(children[i], name)
      if (found) return found
    }

    return null
  }

  // Focus is scene state, so a real window is enough to hold it; it never shows.
  Window {
    id: host
    width: 800
    height: 600
    visible: false
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

        var view = component.createObject(host.contentItem, { width: 800, height: 600, loadBackground: false })
        if (!view) {
          root.fail("LockView failed to instantiate: " + component.errorString())
          return
        }

        var input = root.findByObjectName(view, "passwordInput")
        root.assertTrue(input !== null, "password field exists in the lock view")

        if (input) {
          view.inputEnabled = true
          view.forcePasswordFocus()
          root.assertTrue(input.activeFocus, "password field takes focus when the lock view appears")

          // The lock surface outlives a suspend, so focus can be gone by the
          // time the machine resumes and the view is never rebuilt.
          input.focus = false
          root.assertTrue(!input.activeFocus, "precondition: focus can be lost while the view stays alive")

          // Waking the blanked screen -- a mouse move, not a click. Every wake
          // path goes through this signal, so a move must recover focus too.
          view.wakeRequested()
          root.assertTrue(input.activeFocus, "waking the lock screen restores focus to the password field")

          // The lock preview reuses this view with input disabled; waking it
          // must not hand focus to a field the user cannot type into.
          view.inputEnabled = false
          input.focus = false
          view.wakeRequested()
          root.assertTrue(!input.activeFocus, "waking does not focus the field while input is disabled")
        }

        view.destroy()
      } catch (error) {
        root.fail("lock password focus fixture threw: " + error)
      } finally {
        root.writeResult()
      }
    }
  }
}
