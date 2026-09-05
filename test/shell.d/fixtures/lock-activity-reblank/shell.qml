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

  Item { id: host }

  property var lock: null
  property string lastLoggedBeforeGate: ""
  property int blankPolls: 0

  Timer {
    interval: 1
    running: true
    repeat: false
    onTriggered: {
      try {
        // Load the real lock service. shell: null is fine here -- the parts of
        // Service.qml this fixture exercises (activity re-arm, blank timer,
        // status) never reach into shell.
        var component = Qt.createComponent("file://" + root.rootPath + "/shell/plugins/lock/Service.qml", Component.PreferSynchronous)
        if (component.status !== Component.Ready) {
          root.fail("lock service failed to load: " + component.errorString())
          root.writeResult()
          return
        }

        var lock = component.createObject(host, { shell: null, omarchyPath: root.rootPath })
        if (!lock) {
          root.fail("lock service failed to instantiate: " + component.errorString())
          root.writeResult()
          return
        }
        root.lock = lock

        // 1. Freshly instantiated and unlocked: the activity monitor is off and
        // nothing has armed the blank timer.
        root.assertTrue(lock.activityMonitor.enabled === false, "activity monitor is disabled before any lock is requested")
        root.assertTrue(lock.blankArmed === false, "blank timer is not armed before any lock is requested")
        root.assertTrue(lock.activityMonitor.respectInhibitors === false,
          "inhibitors are not activity: a background video taking one is what lit the panel in #9152")
        root.assertTrue(lock.activityMonitor.timeout < 5,
          "activity monitor's idle timeout is shorter than the blank countdown, got " + lock.activityMonitor.timeout)

        // 2. beginLock() would take a real session lock, which this fixture must
        // never do. Set lockRequested directly instead -- it is exactly the state
        // beginLock() leaves behind, without the WlSessionLock side effect. Doing
        // it this way also proves the bug this test guards: lockRequested alone
        // does not arm the timer, only beginLock() does, so a lock that reaches
        // this state through a real session lock and then goes idle is "lit and
        // spent" until something re-arms it.
        lock.lockRequested = true
        root.assertTrue(lock.activityMonitor.enabled === true, "activity monitor turns on once a lock is requested")
        root.assertTrue(lock.blankArmed === false, "setting lockRequested directly does not arm the blank timer")

        // 3. Raw input activity (an IdleMonitor transition) re-arms it and logs
        // the re-arm.
        lock.handleActivityResumed()
        root.assertTrue(lock.lastEvent === "blank-rearmed: activity",
          "activity re-arm is logged, got " + lock.lastEvent)
        root.assertTrue(lock.blankArmed === true, "activity re-arm arms the blank timer")

        // 4. A password check in flight must never be interrupted by a re-arm.
        lock.authenticatingPassword = true
        root.assertTrue(lock.blankArmed === false, "starting a password check stops the blank timer")
        root.lastLoggedBeforeGate = lock.lastEvent

        lock.handleActivityResumed()
        root.assertTrue(lock.blankArmed === false, "activity during a password check does not re-arm the blank timer")
        root.assertTrue(lock.lastEvent === root.lastLoggedBeforeGate,
          "activity during a password check is not logged as a re-arm, got " + lock.lastEvent)

        lock.authenticatingPassword = false
        root.assertTrue(lock.blankArmed === true, "clearing the password check re-arms the blank timer")

        // 5. Let the re-armed 5000 ms timer run out for real and spawn the blank.
        // This races real input in the live session: any mouse motion or key
        // press re-arms the timer again (silently this time, since it is
        // already running), which is correct behaviour but can keep pushing
        // the deadline out, so give this a generous budget.
        blankPollTimer.start()
      } catch (error) {
        root.fail("lock activity reblank fixture threw: " + error)
        root.writeResult()
      }
    }
  }

  Timer {
    id: blankPollTimer
    interval: 50
    repeat: true
    onTriggered: {
      root.blankPolls++
      var lock = root.lock

      if (lock.lastEvent !== "blank-started" && root.blankPolls < 400) return

      stop()

      root.assertTrue(lock.lastEvent === "blank-started",
        "the re-armed timer spawns the blank within 20s, got " + lock.lastEvent)
      root.assertTrue(lock.blankArmed === false, "the blank timer is spent once it has fired")

      // 6. Unlocking turns the monitor back off, and activity after that point
      // must never re-arm anything.
      lock.lockRequested = false
      root.assertTrue(lock.activityMonitor.enabled === false, "activity monitor turns back off once the lock is released")

      lock.handleActivityResumed()
      root.assertTrue(lock.blankArmed === false, "activity while unlocked never arms the blank timer")
      root.assertTrue(lock.lastEvent === "blank-started",
        "activity while unlocked is not logged as a re-arm, got " + lock.lastEvent)

      lock.destroy()
      root.writeResult()
    }
  }
}
