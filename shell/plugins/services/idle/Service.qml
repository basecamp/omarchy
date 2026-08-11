import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "IdleModel.js" as IdleModel

Item {
  id: root

  // Injected by omarchy-shell (the first-party service loader).
  property var shell: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string stayAwakeStateDir: home + "/.local/state/omarchy/indicators"
  readonly property string stayAwakeStatePath: stayAwakeStateDir + "/stay-awake"
  readonly property int defaultScreensaverSeconds: 150
  readonly property int defaultLockSeconds: 300
  readonly property int defaultScreenOffSeconds: 600
  readonly property var idleConfig: shell && shell.shellConfig && shell.shellConfig.idle ? shell.shellConfig.idle : ({})
  readonly property int screensaverTimeoutSeconds: secondsFromConfig(idleConfig.screensaver, defaultScreensaverSeconds)
  readonly property int lockTimeoutSeconds: secondsFromConfig(idleConfig.lock, defaultLockSeconds)
  readonly property int screenOffTimeoutSeconds: secondsFromConfig(idleConfig.screenOff, defaultScreenOffSeconds)
  // screenOffTimeoutSeconds is a raw config value and can be 0 (the shared
  // idleSchedule() clamps its own first-deadline math, but this timer sits
  // outside that): a configured screenOff: 0 would otherwise make the rearm
  // timer fire on every event-loop tick, blanking the display again the
  // instant it wakes and leaving no way to keep it on.
  readonly property int screenOffRearmSeconds: Math.max(1, screenOffTimeoutSeconds)

  // Locking on idle predates its switch, so it stays on unless turned off.
  // Turning the screens off is new, so it stays off until asked for. Both are
  // compared explicitly: an absent key and an explicit false must not read alike.
  readonly property bool lockOnIdle: idleConfig.lockOnIdle !== false
  readonly property bool screenOffOnIdle: idleConfig.screenOffOnIdle === true

  // A disabled action is passed as null so it takes no part in the shared first
  // idle deadline. The screensaver is always passed: its on/off switch is a state
  // flag the shell cannot see (see bin/omarchy-launch-screensaver), so this switch
  // is armed here even when the launcher will decline.
  readonly property var idleSchedule: IdleModel.idleSchedule(
    screensaverTimeoutSeconds,
    lockOnIdle ? lockTimeoutSeconds : null,
    screenOffOnIdle ? screenOffTimeoutSeconds : null)
  readonly property bool idleArmed: idleSchedule.armed
  readonly property int firstIdleTimeoutSeconds: idleSchedule.firstIdleTimeoutSeconds
  readonly property int screensaverDelaySeconds: idleSchedule.screensaverDelaySeconds
  readonly property int lockDelaySeconds: idleSchedule.lockDelaySeconds
  readonly property int screenOffDelaySeconds: idleSchedule.screenOffDelaySeconds

  // Locking already blanks the screens through its own service. When the lock
  // is due at or before this cycle's screen-off deadline, launching our own
  // blank first would race the lock service's independent wake path with a
  // process it doesn't know about -- the lock subsumes it, so skip it.
  readonly property bool screenOffSubsumedByLock: root.lockOnIdle && root.screenOffDelaySeconds >= root.lockDelaySeconds

  readonly property bool idleEnabled: stayAwakeStateLoaded && !stayAwake
  readonly property string screensaverClass: "org.omarchy.screensaver"

  property bool stayAwake: false
  property bool stayAwakeStateLoaded: false
  property bool hasPendingStayAwakePersist: false
  property bool pendingStayAwakePersist: false
  property bool idledThisCycle: false
  property bool screensaverStartedThisCycle: false
  property bool screenOffThisCycle: false
  property bool wakeAfterBlankPending: false
  property string lastEvent: "starting"
  property string lastEventAt: ""
  property var screensaverWindows: ({})
  property int screensaverWindowCount: 0

  function secondsFromConfig(value, fallback) {
    return IdleModel.secondsFromConfig(value, fallback)
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
    screensaverLaunchGraceTimer.restart()
    runProcess(screensaverProcess, "screensaver", "[[ $(omarchy-shell lock isLocked 2>/dev/null) == \"true\" ]] || omarchy-launch-screensaver")
  }

  // Unlike lockSystem(), this leaves screensaverTimer running: screen-off only
  // disables DPMS output, it doesn't claim the screensaver's window surface the
  // way the lock screen does, so the screensaver stays free to fire on its own
  // configured deadline regardless of what the display is doing.
  function turnOffScreens(reason) {
    logEvent("screen-off", reason || "requested")
    root.screenOffThisCycle = true
    runProcess(screenOffProcess, "screen-off", "omarchy-system-blank")
  }

  // Blank and wake are separate async processes with no ordering between them.
  // If activity lands while omarchy-system-blank is still running, firing wake
  // right away races it -- whichever exits last wins, so the blank can finish
  // after the wake and leave the screens dark despite the cycle being over.
  // Record the request and let flushPendingWake() decide when it's safe to
  // actually launch it.
  function wakeScreens() {
    root.wakeAfterBlankPending = true
    root.flushPendingWake()
  }

  // A pending wake can also fail to launch because wakeProcess itself is
  // still finishing an earlier wake (reachable with the one-second rearm
  // floor: a new blank can complete while the previous wake is still
  // restoring the displays). The flag is only cleared once runProcess()
  // actually starts it, so both screenOffProcess and wakeProcess retry this
  // on exit instead of a busy launch silently dropping the request.
  function flushPendingWake() {
    if (!root.wakeAfterBlankPending) return
    if (screenOffProcess.running) return
    if (!runProcess(wakeProcess, "wake", "omarchy-system-wake")) return
    root.wakeAfterBlankPending = false
  }

  // Turning the screens back on after activity that did not end the cycle. The
  // clock starts over from the full timeout rather than resuming a spent offset:
  // a screen that goes dark the instant you touch the mouse reads as broken.
  function rearmScreenOff() {
    root.screenOffThisCycle = false
    screenOffTimer.stop()
    wakeScreens()
    if (root.screenOffOnIdle) screenOffRearmTimer.restart()
    logEvent("screen-off-wake", root.screenOffRearmSeconds + "s")
  }

  function lockSystem(reason) {
    logEvent("lock-system", reason || "requested")
    screensaverTimer.stop()
    lockTimer.stop()
    // Locking hands the display baton to the lock service, which owns it with a
    // better policy. A surviving screen-off timer would otherwise fire while the
    // user is typing their unlock password, uncancellably: lockSystem clears
    // idledThisCycle and handleActiveSignal early-returns on it.
    screenOffTimer.stop()
    screenOffRearmTimer.stop()
    screensaverLaunchGraceTimer.stop()
    root.idledThisCycle = false
    root.screensaverStartedThisCycle = false
    // The lock service owns the displays from here, so this cycle's blank is no
    // longer ours to report, re-arm, or wake from -- a screen-off blank still
    // finishing in the background (screen-off can legitimately fire before the
    // lock, so this is reachable even outside the subsumed case above) must not
    // un-blank the lock screen once it exits.
    root.screenOffThisCycle = false
    root.wakeAfterBlankPending = false
    resetScreensaverWindows()
    runProcess(lockProcess, "lock", "omarchy-system-lock")
  }

  function startIdleCycle() {
    if (root.idledThisCycle) {
      logEvent("idle-cycle-already-running")
      return
    }

    logEvent("idle-cycle-start", "screensaver=" + root.screensaverTimeoutSeconds
      + " lock=" + (root.lockOnIdle ? root.lockTimeoutSeconds : "off")
      + " screenOff=" + (root.screenOffOnIdle ? root.screenOffTimeoutSeconds : "off"))
    root.idledThisCycle = true
    root.screensaverStartedThisCycle = false
    root.screenOffThisCycle = false
    resetScreensaverWindows()

    if (root.screensaverDelaySeconds === 0) launchScreensaver()
    else screensaverTimer.restart()

    // Armed before the lock: lockSystem() stops every idle timer and a zero delay
    // runs it inline, so anything started after it would outlive its own cycle.
    // Skipped entirely when the lock subsumes this deadline (see
    // screenOffSubsumedByLock): racing our own blank against the lock
    // service's independent wake path would be worse than doing nothing.
    if (root.screenOffOnIdle && !root.screenOffSubsumedByLock) {
      if (root.screenOffDelaySeconds === 0) turnOffScreens("screen-off-immediate")
      else screenOffTimer.restart()
    }

    if (root.lockOnIdle) {
      if (root.lockDelaySeconds === 0) lockSystem("lock-timeout-immediate")
      else lockTimer.restart()
    }
  }

  function cancelIdleCycle(reason) {
    logEvent("idle-cycle-cancel", reason || "requested")
    screensaverTimer.stop()
    lockTimer.stop()
    screenOffTimer.stop()
    screenOffRearmTimer.stop()
    screensaverLaunchGraceTimer.stop()

    if (root.idledThisCycle) wakeScreens()

    root.idledThisCycle = false
    root.screensaverStartedThisCycle = false
    root.screenOffThisCycle = false
    resetScreensaverWindows()
  }

  function resetScreensaverWindows() {
    root.screensaverWindows = ({})
    root.screensaverWindowCount = 0
  }

  function setScreensaverWindow(address, visible) {
    var next = IdleModel.screensaverWindowsAfter(root.screensaverWindows, address, visible)
    root.screensaverWindows = next.windows
    root.screensaverWindowCount = next.count
  }

  function handleScreensaverWindowOpened(address) {
    setScreensaverWindow(address, true)
    screensaverLaunchGraceTimer.stop()
  }

  function handleScreensaverWindowClosed(address) {
    setScreensaverWindow(address, false)

    if (!root.idleEnabled || !root.idledThisCycle || !root.screensaverStartedThisCycle) return
    if (root.screensaverWindowCount > 0) return

    // The user dismissed the screensaver before the lock deadline. Treat that
    // as activity and cancel the pending lock; the lock timer is only allowed
    // to fire while the screensaver remains up.
    root.cancelIdleCycle("screensaver-dismissed")
  }

  function eventParts(event, count) {
    return IdleModel.eventParts(event, count)
  }

  function handleHyprlandEvent(event) {
    var name = String(event && event.name ? event.name : "")
    if (name === "openwindow") {
      var open = eventParts(event, 4)
      if (String(open[2] || "") === root.screensaverClass) root.handleScreensaverWindowOpened(open[0])
    } else if (name === "closewindow") {
      var close = eventParts(event, 1)
      var address = String(close[0] || "")
      if (root.screensaverWindows[address]) root.handleScreensaverWindowClosed(address)
    }
  }

  function handleActiveSignal() {
    if (!root.idledThisCycle) return

    // Starting the screensaver can make the compositor report activity. Keep
    // the lock timer running once the screensaver exists (or during its short
    // launch grace); Hyprland window events cancel the cycle if it exits before
    // the normal lock deadline.
    if (root.screensaverStartedThisCycle && (root.screensaverWindowCount > 0 || screensaverLaunchGraceTimer.running)) {
      // The screensaver keeps the cycle armed through the activity it provokes
      // when it maps, so this branch is also where a real bump lands while the
      // panels are asleep. Restore them and take a fresh run-up: leaving the
      // displays dark for the rest of the cycle -- or lit, once the timer is
      // spent -- is the failure this feature exists to prevent.
      if (root.screenOffThisCycle) rearmScreenOff()
      logEvent("idle-monitor-active", "screensaver cycle remains armed")
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
      stayAwake: root.stayAwake,
      stayAwakeStateLoaded: root.stayAwakeStateLoaded,
      stayAwakeStatePath: root.stayAwakeStatePath,
      idle: idleMonitor.isIdle,
      inIdleCycle: root.idledThisCycle,
      screensaverStarted: root.screensaverStartedThisCycle,
      armed: root.idleArmed,
      screensaver: root.screensaverTimeoutSeconds,
      lock: root.lockTimeoutSeconds,
      lockOnIdle: root.lockOnIdle,
      screenOff: root.screenOffTimeoutSeconds,
      screenOffOnIdle: root.screenOffOnIdle,
      screensaverDelay: root.screensaverDelaySeconds,
      lockDelay: root.lockDelaySeconds,
      screenOffDelay: root.screenOffDelaySeconds,
      screenOffActive: root.screenOffThisCycle,
      screenOffWatcherEnabled: screenOffActivityMonitor.enabled,
      screenOffWatcherIdle: screenOffActivityMonitor.isIdle,
      wakeAfterBlankPending: root.wakeAfterBlankPending,
      screensaverWindows: root.screensaverWindowCount,
      timers: {
        screensaver: screensaverTimer.running,
        lock: lockTimer.running,
        screenOff: screenOffTimer.running,
        screenOffRearm: screenOffRearmTimer.running,
        screensaverLaunchGrace: screensaverLaunchGraceTimer.running
      },
      processes: {
        screensaver: screensaverProcess.running,
        lock: lockProcess.running,
        screenOff: screenOffProcess.running,
        wake: wakeProcess.running
      },
      lastEvent: root.lastEvent,
      lastEventAt: root.lastEventAt
    })
  }

  function persistStayAwake(value) {
    var command = value
      ? "mkdir -p \"$HOME/.local/state/omarchy/indicators\" && touch \"$HOME/.local/state/omarchy/indicators/stay-awake\""
      : "rm -f \"$HOME/.local/state/omarchy/indicators/stay-awake\""

    if (stayAwakeStateWriter.running) {
      root.pendingStayAwakePersist = !!value
      root.hasPendingStayAwakePersist = true
      return
    }

    stayAwakeStateWriter.command = ["bash", "-lc", command]
    stayAwakeStateWriter.running = true
  }

  function refreshStayAwakeState() {
    if (!stayAwakeStateProbe.running) stayAwakeStateProbe.running = true
  }

  function applyStayAwake(value, persist, reason) {
    var enabled = !!value
    var changed = !root.stayAwakeStateLoaded || root.stayAwake !== enabled

    if (persist) persistStayAwake(enabled)

    root.stayAwake = enabled
    root.stayAwakeStateLoaded = true

    if (!changed) return enabled ? "disabled" : "enabled"

    logEvent("stay-awake", (enabled ? "enabled" : "disabled") + (reason ? " " + reason : ""))
    if (enabled) cancelIdleCycle("stay-awake")
    else Qt.callLater(root.handleIdleChanged)

    return enabled ? "disabled" : "enabled"
  }

  function setIdleEnabled(value) {
    return applyStayAwake(!value, true, "ipc")
  }

  IdleMonitor {
    id: idleMonitor
    // A zero timeout means "report idle immediately" to ext-idle-notify, so when
    // nothing is armed the monitor is stopped rather than handed a deadline.
    enabled: root.idleEnabled && root.idleArmed
    timeout: root.firstIdleTimeoutSeconds
    respectInhibitors: true
    onIsIdleChanged: root.handleIdleChanged()
  }

  IdleMonitor {
    id: screenOffActivityMonitor
    // ext-idle-notify only reports "resumed" on the way out of idle, and the
    // screensaver's launch activity can spend the main monitor's transition
    // (see handleActiveSignal) before a later blank. Real input after that
    // blank would then go unseen until the main monitor re-idled, leaving the
    // panels dark under a moving mouse. This watcher exists only while the
    // screens are off -- the user is by definition idle, so it re-idles within
    // a second and its own resumed edge relights them. Inhibitors are ignored:
    // only raw input should wake a blanked display.
    enabled: root.idleEnabled && root.screenOffThisCycle
    timeout: 1
    respectInhibitors: false
    onIsIdleChanged: {
      // Disabling a monitor resets isIdle to false and re-enters this handler,
      // so every path that clears screenOffThisCycle or idleEnabled lands here
      // before this runs: both are re-checked instead of trusting the binding.
      if (isIdle || !root.idleEnabled || !root.screenOffThisCycle) return
      root.logEvent("screen-off-activity", "input while screens are dark")
      root.handleActiveSignal()
    }
  }

  Timer {
    id: screensaverTimer
    interval: root.screensaverDelaySeconds * 1000
    repeat: false
    onTriggered: root.launchScreensaver()
  }

  Timer {
    id: screenOffTimer
    // The offset from the shared idle notification: the first blank of a cycle.
    interval: root.screenOffDelaySeconds * 1000
    repeat: false
    onTriggered: if (root.screenOffOnIdle && !root.screenOffSubsumedByLock && root.idleEnabled && root.idledThisCycle) root.turnOffScreens("screen-off-timeout")
  }

  Timer {
    id: screenOffRearmTimer
    // The full timeout: after activity that did not end the cycle, the clock
    // starts over rather than resuming a spent offset.
    interval: root.screenOffRearmSeconds * 1000
    repeat: false
    onTriggered: if (root.screenOffOnIdle && !root.screenOffSubsumedByLock && root.idleEnabled && root.idledThisCycle) root.turnOffScreens("screen-off-rearmed")
  }

  Timer {
    id: lockTimer
    interval: root.lockDelaySeconds * 1000
    repeat: false
    onTriggered: if (root.lockOnIdle && root.idleEnabled && root.idledThisCycle) root.lockSystem("lock-timeout")
  }

  // A switch flipped mid-cycle applies to that cycle, not the next one. Turning
  // an action off disarms it; turning it on arms it against the deadline the
  // schedule already computed. A zero delay is deliberately not fired here: a
  // config write means someone is at a keyboard, and locking or blanking under
  // them would be rude.
  function syncSwitchTimer(enabled, timer, delaySeconds) {
    if (!enabled) {
      timer.stop()
      return
    }
    if (!root.idleEnabled || !root.idledThisCycle || timer.running) return
    if (delaySeconds > 0) timer.restart()
  }

  onLockOnIdleChanged: syncSwitchTimer(root.lockOnIdle, lockTimer, root.lockDelaySeconds)

  // Lock is never subsumed by screen-off -- only screen-off can be subsumed by
  // lock (screenOffSubsumedByLock), since lock is the deadline being compared
  // against.
  onScreenOffOnIdleChanged: {
    syncSwitchTimer(root.screenOffOnIdle && !root.screenOffSubsumedByLock, screenOffTimer, root.screenOffDelaySeconds)
    if (root.screenOffOnIdle) return
    screenOffRearmTimer.stop()
    // Turning the switch off while the panels are already asleep must not leave
    // the user in front of a dark screen.
    if (root.screenOffThisCycle) {
      root.screenOffThisCycle = false
      wakeScreens()
    }
  }

  Timer {
    id: screensaverLaunchGraceTimer
    interval: 3000
    repeat: false
    onTriggered: {
      if (root.idleEnabled && root.idledThisCycle && root.screensaverStartedThisCycle && root.screensaverWindowCount === 0 && !idleMonitor.isIdle) {
        root.cancelIdleCycle("screensaver-not-running")
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
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
    id: screenOffProcess
    onExited: function(exitCode, exitStatus) {
      root.logEvent("process-exit", "screen-off exitCode=" + exitCode + " status=" + exitStatus)
      root.flushPendingWake()
    }
  }
  Process {
    id: wakeProcess
    onExited: function(exitCode, exitStatus) {
      root.logEvent("process-exit", "wake exitCode=" + exitCode + " status=" + exitStatus)
      root.flushPendingWake()
    }
  }

  Process {
    id: stayAwakeStateProbe
    command: ["bash", "-c", "mkdir -p \"$HOME/.local/state/omarchy/indicators\"; if [[ -f $HOME/.local/state/omarchy/indicators/stay-awake ]]; then echo yes; else echo no; fi"]
    stdout: SplitParser {
      onRead: function(line) { root.applyStayAwake(String(line).trim() === "yes", false, "state-file") }
    }
    onExited: function() { stayAwakeStateDirWatcher.reload() }
  }

  Process {
    id: stayAwakeStateWriter
    onExited: function() {
      if (root.hasPendingStayAwakePersist) {
        var pending = root.pendingStayAwakePersist
        root.hasPendingStayAwakePersist = false
        root.persistStayAwake(pending)
        return
      }

      root.refreshStayAwakeState()
    }
  }

  FileView {
    id: stayAwakeStateDirWatcher
    path: root.stayAwakeStateDir
    watchChanges: true
    printErrors: false
    onFileChanged: root.refreshStayAwakeState()
  }

  Component.onCompleted: {
    logEvent("service-ready")
    refreshStayAwakeState()
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
