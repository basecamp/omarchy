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

  function runProcess(process, command) {
    if (process.running) return false
    process.command = ["bash", "-lc", command]
    process.running = true
    return true
  }

  function launchScreensaver() {
    root.screensaverStartedThisCycle = true
    runProcess(screensaverProcess, "pidof hyprlock >/dev/null || omarchy-launch-screensaver")
  }

  function lockSystem() {
    screensaverTimer.stop()
    lockTimer.stop()
    screensaverResumePollTimer.stop()
    root.idledThisCycle = false
    root.screensaverStartedThisCycle = false
    runProcess(lockProcess, "omarchy-system-lock")
  }

  function startIdleCycle() {
    if (root.idledThisCycle) return

    root.idledThisCycle = true
    root.screensaverStartedThisCycle = false
    screensaverResumePollTimer.stop()

    if (root.screensaverDelaySeconds === 0) launchScreensaver()
    else screensaverTimer.restart()

    if (root.lockDelaySeconds === 0) lockSystem()
    else lockTimer.restart()
  }

  function cancelIdleCycle() {
    screensaverTimer.stop()
    lockTimer.stop()
    screensaverResumePollTimer.stop()

    if (root.idledThisCycle) runProcess(wakeProcess, "omarchy-system-wake")

    root.idledThisCycle = false
    root.screensaverStartedThisCycle = false
  }

  function checkScreensaverAfterActiveSignal() {
    if (!root.idledThisCycle || !root.screensaverStartedThisCycle) return
    if (screensaverCheckProcess.running) return
    screensaverCheckProcess.command = ["bash", "-lc", "pgrep -f org.omarchy.screensaver >/dev/null && echo running || echo stopped"]
    screensaverCheckProcess.running = true
  }

  function handleActiveSignal() {
    if (!root.idledThisCycle) return

    // Starting the screensaver can make the compositor report activity. Keep
    // the lock timer running while the screensaver is still alive so the lock
    // deadline remains `idle.lock` seconds from the original user idle time.
    if (root.screensaverStartedThisCycle) {
      screensaverResumePollTimer.restart()
      return
    }

    cancelIdleCycle()
  }

  function handleIdleChanged() {
    if (!root.idleEnabled) return

    if (idleMonitor.isIdle) startIdleCycle()
    else handleActiveSignal()
  }

  function statusJson() {
    return JSON.stringify({
      enabled: root.idleEnabled,
      idle: idleMonitor.isIdle,
      inIdleCycle: root.idledThisCycle,
      sleepMonitor: sleepMonitorProcess.running,
      screensaver: root.screensaverTimeoutSeconds,
      lock: root.lockTimeoutSeconds
    })
  }

  function handleSleepPreparing(preparing) {
    if (!root.idleEnabled) return

    if (preparing) {
      cancelIdleCycle()
      runProcess(sleepLockProcess, "OMARCHY_LOCK_ONLY=true omarchy-system-lock")
    } else {
      runProcess(sleepWakeProcess, "sleep 1 && omarchy-system-wake")
    }
  }

  function setIdleEnabled(value) {
    var enabled = !!value
    if (persisted.idleEnabled === enabled) return enabled ? "enabled" : "disabled"

    persisted.idleEnabled = enabled
    if (!enabled) cancelIdleCycle()
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
    onTriggered: if (root.idleEnabled && root.idledThisCycle) root.lockSystem()
  }

  Timer {
    id: screensaverResumePollTimer
    interval: 1000
    repeat: true
    onTriggered: root.checkScreensaverAfterActiveSignal()
  }

  Process { id: screensaverProcess }
  Process { id: lockProcess }
  Process { id: wakeProcess }
  Process { id: sleepLockProcess }
  Process { id: sleepWakeProcess }

  Process {
    id: screensaverCheckProcess
    stdout: StdioCollector {
      id: screensaverCheckStdout
      waitForEnd: true
    }
    onExited: {
      if (!root.idledThisCycle || !root.screensaverStartedThisCycle) return
      if (String(screensaverCheckStdout.text || "").trim() === "running") return
      root.cancelIdleCycle()
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
    onExited: sleepMonitorRestartTimer.restart()
  }

  Timer {
    id: sleepMonitorRestartTimer
    interval: 5000
    repeat: false
    onTriggered: if (!sleepMonitorProcess.running) sleepMonitorProcess.running = true
  }

  Component.onCompleted: Qt.callLater(root.handleIdleChanged)

  IpcHandler {
    target: "idle"

    function status(): string {
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
