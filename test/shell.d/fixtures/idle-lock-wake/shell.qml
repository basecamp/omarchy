import QtQuick
import Quickshell

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

  // Stand-ins for the lock service and for the shell that hands services out,
  // shaped like the real ones as far as the idle service reads them. Services
  // register by reassigning _services, as shell.qml does, so the fixture can
  // check that the idle service picks up a lock service that arrives after it.
  // The timeouts keep the real IdleMonitor and lock timer from ever firing
  // against the developer's session if this instance outlives the test.
  QtObject {
    id: fakeLock
    property bool locked: true
  }

  QtObject {
    id: fakeShell
    property var shellConfig: ({ idle: { screensaver: 86400, lock: 86400 } })
    property var _services: ({})
    function serviceFor(pluginId) {
      return _services[String(pluginId)] || null
    }
    function firstPartyServiceFor(pluginId) {
      return serviceFor(pluginId)
    }
  }

  Item { id: host }

  Timer {
    interval: 1
    running: true
    repeat: false
    onTriggered: {
      try {
        var component = Qt.createComponent("file://" + root.rootPath + "/shell/plugins/services/idle/Service.qml", Component.PreferSynchronous)
        if (component.status !== Component.Ready) {
          root.fail("idle service failed to load: " + component.errorString())
          return
        }

        var idle = component.createObject(host, { shell: fakeShell })
        if (!idle) {
          root.fail("idle service failed to instantiate: " + component.errorString())
          return
        }

        root.assertTrue(idle.sessionLocked === false, "idle service reads unlocked before any lock service exists")

        // The lock service registers after the idle service, the way shell.qml
        // can load them in either order.
        var services = ({})
        services["omarchy.lock"] = fakeLock
        fakeShell._services = services
        root.assertTrue(idle.sessionLocked === true, "idle service picks up a lock service registered after it")

        // Locked: the monitor's "active" ends the cycle, but the display is left
        // to the lock screen.
        idle.idledThisCycle = true
        idle.handleActiveSignal()
        var locked = JSON.parse(idle.statusJson())
        root.assertTrue(locked.sessionLocked === true, "idle status reports the locked session")
        root.assertTrue(locked.processes.wake === false, "no wake process is spawned while the session is locked")
        root.assertTrue(locked.lastEvent === "wake-skipped: session-locked",
          "the skipped wake is logged, got " + locked.lastEvent)
        root.assertTrue(locked.inIdleCycle === false, "the idle cycle still ends while locked")

        // Unlocked: the same signal wakes the display as before.
        fakeLock.locked = false
        root.assertTrue(idle.sessionLocked === false, "idle service follows the lock service back to unlocked")
        idle.idledThisCycle = true
        idle.handleActiveSignal()
        var unlocked = JSON.parse(idle.statusJson())
        root.assertTrue(unlocked.sessionLocked === false, "idle status reports the unlocked session")
        root.assertTrue(unlocked.processes.wake === true, "the wake process is spawned once the session is unlocked")
        root.assertTrue(unlocked.lastEvent === "process-start: wake omarchy-system-wake",
          "the wake is logged as started, got " + unlocked.lastEvent)

        // Let the spawned wake finish before tearing the service down, or the
        // Process dies with it and the test's marker never lands.
        root.idle = idle
        finishTimer.start()
      } catch (error) {
        root.fail("idle lock wake fixture threw: " + error)
        root.writeResult()
      }
    }
  }

  property var idle: null
  property int finishPolls: 0

  Timer {
    id: finishTimer
    interval: 50
    repeat: true
    onTriggered: {
      root.finishPolls++
      var status = JSON.parse(root.idle.statusJson())
      if (status.processes.wake && root.finishPolls < 100) return
      root.assertTrue(!status.processes.wake, "the wake process exits within five seconds")
      finishTimer.stop()
      root.idle.destroy()
      root.writeResult()
    }
  }
}
