import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Item {
  id: root

  // Injected by omarchy-shell (the first-party service loader).
  property var shell: null

  readonly property int defaultScreensaverSeconds: 150
  readonly property int defaultLockSeconds: 300
  readonly property var idleConfig: shell && shell.shellConfig && shell.shellConfig.idle ? shell.shellConfig.idle : ({})
  readonly property int screensaverTimeoutSeconds: secondsFromConfig(idleConfig.screensaver, defaultScreensaverSeconds)
  readonly property int lockTimeoutSeconds: secondsFromConfig(idleConfig.lock, defaultLockSeconds)
  readonly property int firstIdleTimeoutSeconds: Math.min(screensaverTimeoutSeconds, lockTimeoutSeconds)
  readonly property int screensaverDelaySeconds: Math.max(0, screensaverTimeoutSeconds - firstIdleTimeoutSeconds)
  readonly property int lockDelaySeconds: Math.max(0, lockTimeoutSeconds - firstIdleTimeoutSeconds)
  readonly property bool idleEnabled: persisted.idleEnabled

  property bool idledThisCycle: false
  property bool screensaverStartedThisCycle: false
  property string lastEvent: "starting"
  property string lastEventAt: ""
  property string lastScreensaverState: "unknown"
  property string lastScreensaverCheckAt: ""
  property int screensaverCheckCount: 0

  PersistentProperties {
    id: persisted
    reloadableId: "omarchy-idle"
    property bool idleEnabled: true
  }

  function secondsFromConfig(value, fallback) {
    var n = Number(value)
    if (!isFinite(n) || n < 0) return fallback
    return Math.floor(n)
  }

  function nowIso() {
    return new Date().toISOString()
  }

  function logEvent(event, details) {
    var suffix = details === undefined || details === null || details === "" ? "" : ": " + String(details)
    root.lastEventAt = nowIso()
    root.lastEvent = event + suffix
    console.log("omarchy idle " + root.lastEventAt + " " + root.lastEvent)
  }

  function runProcess(process, label, command) {
    if (process.running) {
      logEvent("process-skip", label + " already running")
      return false
    }
    logEvent("process-start", label + " " + command)
    process.command = ["bash", "-lc", command]
    process.running = true
    return true
  }

  function launchScreensaver() {
    root.screensaverStartedThisCycle = true
    screensaverResumePollTimer.restart()
    runProcess(screensaverProcess, "screensaver", "[[ $(omarchy-shell lock isLocked 2>/dev/null) == \"true\" ]] || omarchy-launch-screensaver")
  }

  function lockSystem(reason) {
    logEvent("lock-system", reason || "requested")
    screensaverTimer.stop()
    lockTimer.stop()
    screensaverResumePollTimer.stop()
    root.idledThisCycle = false
    root.screensaverStartedThisCycle = false
    runProcess(lockProcess, "lock", "omarchy-system-lock")
  }

  function startIdleCycle() {
    if (root.idledThisCycle) {
      logEvent("idle-cycle-already-running")
      return
    }

    logEvent("idle-cycle-start", "screensaver=" + root.screensaverTimeoutSeconds + " lock=" + root.lockTimeoutSeconds)
    root.idledThisCycle = true
    root.screensaverStartedThisCycle = false
    screensaverResumePollTimer.stop()

    if (root.screensaverDelaySeconds === 0) launchScreensaver()
    else screensaverTimer.restart()

    if (root.lockDelaySeconds === 0) lockSystem("lock-timeout-immediate")
    else lockTimer.restart()
  }

  function cancelIdleCycle(reason) {
    logEvent("idle-cycle-cancel", reason || "requested")
    screensaverTimer.stop()
    lockTimer.stop()
    screensaverResumePollTimer.stop()

    if (root.idledThisCycle) runProcess(wakeProcess, "wake", "omarchy-system-wake")

    root.idledThisCycle = false
    root.screensaverStartedThisCycle = false
  }

  function checkScreensaverAfterActiveSignal() {
    if (!root.idledThisCycle || !root.screensaverStartedThisCycle) return
    if (screensaverCheckProcess.running) return
    root.lastScreensaverState = "checking"
    root.lastScreensaverCheckAt = nowIso()
    screensaverCheckProcess.command = ["bash", "-lc", "if hyprctl clients -j 2>/dev/null | jq -e '.[] | select(.class == \"org.omarchy.screensaver\" or .initialClass == \"org.omarchy.screensaver\")' >/dev/null; then echo running-window; elif pgrep -f '[o]rg.omarchy.screensaver' >/dev/null; then echo running-process; elif omarchy-toggle-enabled screensaver-off; then echo disabled; else echo stopped; fi"]
    screensaverCheckProcess.running = true
  }

  function handleActiveSignal() {
    if (!root.idledThisCycle) return

    // Starting the screensaver can make the compositor report activity. Keep
    // the lock timer running while the screensaver is still alive so the lock
    // deadline remains `idle.lock` seconds from the original user idle time.
    if (root.screensaverStartedThisCycle) {
      logEvent("idle-monitor-active", "screensaver cycle remains armed")
      screensaverResumePollTimer.restart()
      return
    }

    cancelIdleCycle("activity")
  }

  function handleIdleChanged() {
    logEvent("idle-monitor", idleMonitor.isIdle ? "idle" : "active")
    if (!root.idleEnabled) return

    if (idleMonitor.isIdle) startIdleCycle()
    else handleActiveSignal()
  }

  function statusJson() {
    return JSON.stringify({
      enabled: root.idleEnabled,
      idle: idleMonitor.isIdle,
      inIdleCycle: root.idledThisCycle,
      screensaverStarted: root.screensaverStartedThisCycle,
      sleepMonitor: sleepMonitorProcess.running,
      screensaver: root.screensaverTimeoutSeconds,
      lock: root.lockTimeoutSeconds,
      screensaverDelay: root.screensaverDelaySeconds,
      lockDelay: root.lockDelaySeconds,
      timers: {
        screensaver: screensaverTimer.running,
        lock: lockTimer.running,
        poll: screensaverResumePollTimer.running,
        sleepMonitorRestart: sleepMonitorRestartTimer.running
      },
      processes: {
        screensaver: screensaverProcess.running,
        lock: lockProcess.running,
        wake: wakeProcess.running,
        check: screensaverCheckProcess.running,
        sleepLock: sleepLockProcess.running,
        sleepWake: sleepWakeProcess.running
      },
      lastEvent: root.lastEvent,
      lastEventAt: root.lastEventAt,
      lastScreensaverState: root.lastScreensaverState,
      lastScreensaverCheckAt: root.lastScreensaverCheckAt,
      screensaverCheckCount: root.screensaverCheckCount
    })
  }

  function handleSleepPreparing(preparing) {
    if (!root.idleEnabled) return

    if (preparing) {
      cancelIdleCycle("sleep-preparing")
      runProcess(sleepLockProcess, "sleep-lock", "OMARCHY_LOCK_ONLY=true omarchy-system-lock")
    } else {
      runProcess(sleepWakeProcess, "sleep-wake", "sleep 1 && omarchy-system-wake")
    }
  }

  function setIdleEnabled(value) {
    var enabled = !!value
    if (persisted.idleEnabled === enabled) return enabled ? "enabled" : "disabled"

    persisted.idleEnabled = enabled
    logEvent("idle-enabled", enabled ? "enabled" : "disabled")
    if (!enabled) cancelIdleCycle("disabled")
    else Qt.callLater(root.handleIdleChanged)

    return enabled ? "enabled" : "disabled"
  }

  IdleMonitor {
    id: idleMonitor
    enabled: root.idleEnabled
    timeout: root.firstIdleTimeoutSeconds
    respectInhibitors: true
    onIsIdleChanged: root.handleIdleChanged()
  }

  Timer {
    id: screensaverTimer
    interval: root.screensaverDelaySeconds * 1000
    repeat: false
    onTriggered: root.launchScreensaver()
  }

  Timer {
    id: lockTimer
    interval: root.lockDelaySeconds * 1000
    repeat: false
    onTriggered: if (root.idleEnabled && root.idledThisCycle) root.lockSystem("lock-timeout")
  }

  Timer {
    id: screensaverResumePollTimer
    interval: 1000
    repeat: true
    onTriggered: root.checkScreensaverAfterActiveSignal()
  }

  Process {
    id: screensaverProcess
    onExited: function(exitCode, exitStatus) { root.logEvent("process-exit", "screensaver exitCode=" + exitCode + " status=" + exitStatus) }
  }
  Process {
    id: lockProcess
    onExited: function(exitCode, exitStatus) { root.logEvent("process-exit", "lock exitCode=" + exitCode + " status=" + exitStatus) }
  }
  Process {
    id: wakeProcess
    onExited: function(exitCode, exitStatus) { root.logEvent("process-exit", "wake exitCode=" + exitCode + " status=" + exitStatus) }
  }
  Process {
    id: sleepLockProcess
    onExited: function(exitCode, exitStatus) { root.logEvent("process-exit", "sleep-lock exitCode=" + exitCode + " status=" + exitStatus) }
  }
  Process {
    id: sleepWakeProcess
    onExited: function(exitCode, exitStatus) { root.logEvent("process-exit", "sleep-wake exitCode=" + exitCode + " status=" + exitStatus) }
  }

  Process {
    id: screensaverCheckProcess
    stdout: SplitParser {
      onRead: function(line) {
        root.lastScreensaverState = String(line || "").trim()
        root.lastScreensaverCheckAt = root.nowIso()
        root.screensaverCheckCount++
        root.logEvent("screensaver-check", root.lastScreensaverState)
      }
    }
    onExited: function(exitCode, exitStatus) {
      root.logEvent("process-exit", "screensaver-check exitCode=" + exitCode + " status=" + exitStatus + " state=" + root.lastScreensaverState)
      if (!root.idleEnabled || !root.idledThisCycle || !root.screensaverStartedThisCycle) return

      var state = String(root.lastScreensaverState || "").trim()
      if (state.indexOf("running") === 0) return
      if (state === "disabled") {
        screensaverResumePollTimer.stop()
        return
      }

      // If the screensaver disappears while we're still in the idle cycle,
      // treat that as the user returning and require authentication before
      // showing the desktop again.
      root.lockSystem("screensaver-stopped state=" + state)
    }
  }

  Process {
    id: sleepMonitorProcess
    command: ["bash", "-lc", "exec dbus-monitor --system \"type='signal',sender='org.freedesktop.login1',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'\""]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        var text = String(line || "").trim()
        if (text === "boolean true") root.handleSleepPreparing(true)
        else if (text === "boolean false") root.handleSleepPreparing(false)
      }
    }
    onExited: {
      root.logEvent("sleep-monitor-exit", "restarting")
      sleepMonitorRestartTimer.restart()
    }
  }

  Timer {
    id: sleepMonitorRestartTimer
    interval: 5000
    repeat: false
    onTriggered: {
      if (!sleepMonitorProcess.running) {
        root.logEvent("sleep-monitor-restart")
        sleepMonitorProcess.running = true
      }
    }
  }

  Component.onCompleted: {
    logEvent("service-ready")
    Qt.callLater(root.handleIdleChanged)
  }

  IpcHandler {
    target: "idle"

    function status(): string {
      return root.statusJson()
    }

    function debug(): string {
      return root.statusJson()
    }

    function enable(): string {
      return root.setIdleEnabled(true)
    }

    function disable(): string {
      return root.setIdleEnabled(false)
    }

    function toggle(): string {
      return root.setIdleEnabled(!root.idleEnabled)
    }
  }
}
