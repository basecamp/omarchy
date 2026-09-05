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
  property bool screensaverActivityExpected: false
  property bool screenOffThisCycle: false
  property string pendingDisplayState: ""
  property string pendingLockReason: ""
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
    // Mapping the screensaver makes the compositor report activity; claim that
    // one report here so handleActiveSignal can tell it from a real bump.
    root.screensaverActivityExpected = true
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
    root.pendingDisplayState = "blank"
    flushDisplayState()
  }

  function wakeScreens() {
    root.pendingDisplayState = "wake"
    flushDisplayState()
  }

  // Blanking and waking are one resource seen from two sides: two async
  // processes that must never overlap, because whichever exits last decides
  // what the displays actually do. Launching either while the other is still
  // running races it; refusing to launch drops the request entirely. So the
  // wanted end state is recorded instead -- the newest request wins, since
  // wanting the screens on then off (or the reverse) is not a queue to work
  // through -- and it only clears once the process for it really started.
  // Both processes flush on exit, so a request made while one was busy is
  // retried rather than lost. Reachable with the one-second rearm floor: a
  // reblank can come due while the previous wake is still restoring.
  function flushDisplayState() {
    if (!root.pendingDisplayState) return
    if (screenOffProcess.running || wakeProcess.running) return
    var started = root.pendingDisplayState === "blank"
      ? runProcess(screenOffProcess, "screen-off", "omarchy-system-blank")
      : runProcess(wakeProcess, "wake", "omarchy-system-wake")
    if (started) root.pendingDisplayState = ""
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
    root.screensaverActivityExpected = false
    // The lock service owns the displays from here, so this cycle's blank is no
    // longer ours to report, re-arm, or wake from -- a screen-off blank still
    // finishing in the background (screen-off can legitimately fire before the
    // lock, so this is reachable even outside the subsumed case above) must not
    // un-blank the lock screen once it exits.
    root.screenOffThisCycle = false
    root.pendingDisplayState = ""
    resetScreensaverWindows()
    // The lock service starts its own, independent wake as soon as the user
    // interacts, with no way to know a blank from here is still in flight. If
    // that wake finishes first, the stale blank disabling DPMS afterward would
    // leave the unlock screen dark. Wait for it to actually exit before handing
    // display ownership over, instead of racing the two.
    if (screenOffProcess.running) {
      root.pendingLockReason = reason || "requested"
      return
    }
    runProcess(lockProcess, "lock", "omarchy-system-lock")
  }

  function flushPendingLock() {
    if (!root.pendingLockReason) return
    var reason = root.pendingLockReason
    root.pendingLockReason = ""
    logEvent("lock-system-deferred", reason)
    runProcess(lockProcess, "lock", "omarchy-system-lock")
  }

  // Dropping a deferred lock takes the displays back from a lock service that
  // never got them: lockSystem() disowned this cycle's screen-off and its
  // wanted display state on the promise the lock would follow, and it also
  // ended the cycle, so nothing else here is still watching. Without a wake
  // the blank it is waiting on lands on screens with no lock in front of them
  // and no armed cycle to notice. A lock is only ever deferred behind a
  // running blank, so waking is always what is wanted.
  function cancelPendingLock() {
    if (!root.pendingLockReason) return
    logEvent("lock-system-cancelled", root.pendingLockReason)
    root.pendingLockReason = ""
    wakeScreens()
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
    root.screensaverActivityExpected = false
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
    root.screensaverActivityExpected = false
    root.screenOffThisCycle = false
    // A lock deferred by lockSystem() (waiting on an in-flight screen-off
    // blank) is still just a decision, not yet a running process -- activity,
    // or Stay Awake turning on, cancels it like everything else here instead
    // of locking anyway once the blank happens to finish. The wake above is
    // gated on idledThisCycle, which lockSystem() already cleared, so
    // cancelling the lock has to take that wake back over.
    cancelPendingLock()
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
      // spent -- is the failure this feature exists to prevent. The mapping
      // itself is not a bump, though, and screen-off can be configured ahead
      // of the screensaver: that report lands on already-dark panels, and
      // relighting them for it would wake a screen nobody asked to wake.
      if (root.screensaverActivityExpected) root.screensaverActivityExpected = false
      else if (root.screenOffThisCycle) rearmScreenOff()
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
      pendingDisplayState: root.pendingDisplayState,
      pendingLockReason: root.pendingLockReason,
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
    // panels dark under a moving mouse. This watcher runs for the whole idle
    // cycle rather than only while the screens are off: with a one-second
    // timeout it needs a second of quiet to go idle before it has a resumed
    // edge to give, and starting it at the blank would spend that second with
    // the screens already dark, missing the input that lands inside it. The
    // handler below stays gated on the screens actually being off, so the
    // extra arming costs nothing. Inhibitors are ignored: only raw input
    // should wake a blanked display.
    enabled: root.idleEnabled && root.idledThisCycle
    timeout: 1
    respectInhibitors: false
    onIsIdleChanged: {
      // Disabling a monitor resets isIdle to false and re-enters this handler,
      // and both cycle-ending paths drop idledThisCycle before this cycle's
      // screen-off ownership, so that re-entry arrives while the blank still
      // looks like ours. Every term is re-checked instead of trusting the
      // binding, or ending a cycle would report input nobody gave.
      if (isIdle || !root.idleEnabled || !root.idledThisCycle || !root.screenOffThisCycle) return
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

  onLockOnIdleChanged: {
    syncSwitchTimer(root.lockOnIdle, lockTimer, root.lockDelaySeconds)
    // This switch also decides screenOffSubsumedByLock, so screen-off is
    // resynced against the new verdict: turning the lock off un-subsumes a
    // screen-off this cycle skipped, and turning it on leaves one armed that
    // the lock now covers.
    syncSwitchTimer(root.screenOffOnIdle && !root.screenOffSubsumedByLock, screenOffTimer, root.screenOffDelaySeconds)
    if (root.lockOnIdle) return
    // Only the idle timeout defers a lock, so turning that off cancels one
    // still waiting behind a blank -- exactly like the timer above.
    cancelPendingLock()
  }

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
      root.flushDisplayState()
      root.flushPendingLock()
    }
  }
  Process {
    id: wakeProcess
    onExited: function(exitCode, exitStatus) {
      root.logEvent("process-exit", "wake exitCode=" + exitCode + " status=" + exitStatus)
      root.flushDisplayState()
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
