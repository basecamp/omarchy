import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"

  property bool lockRequested: false
  property bool pendingSessionLock: false
  property bool wakeRerunRequested: false
  property bool keyboardBlanked: false
  // Only true once runBlank() itself actually ran the real "off": that
  // captures whatever was current via brightnessctl's own save, correct
  // regardless of whether a software or a hardware-driven change put it
  // there. The poll-tracked value below only ever fills in for the one case
  // that leaves this false while keyboardBlanked is still true: a suspend
  // detected without the idle-blank timer ever having gotten a turn.
  property bool keyboardOffSaved: false
  property string kbdDeviceName: ""
  property string kbdBrightnessPath: ""
  property int savedKeyboardBrightness: -1
  // Tied directly to lock state rather than toggled by hand: manual toggling
  // around individual wake/blank events kept getting this wrong whenever one
  // of the several *other* wakes a lock session runs (nudges, retries) fired
  // and cleared it while still locked, letting the poll below corrupt the
  // frozen value before the real unlock ever got to use it.
  readonly property bool kbdTrackingSuspended: locked
  property bool authenticatingPassword: false
  property bool fingerprintAuthenticating: false
  property bool passwordPamConfigured: false
  property bool fingerprintConfigured: false
  property bool previewVisible: false
  property string enteredPassword: ""
  property string pendingPassword: ""
  property string failureMessage: ""
  property int failedAttempts: 0
  property string backgroundPath: ""
  property int backgroundVersion: 0
  property string lastEvent: "init"
  property string lastEventAt: ""
  property bool strandedLock: false
  property bool strandedLockResolved: false

  readonly property bool locked: lockRequested || sessionLock.locked || sessionLock.secure
  readonly property bool authenticating: authenticatingPassword || fingerprintAuthenticating

  function realScreenCount() {
    var screens = Quickshell.screens || []
    var count = 0

    for (var i = 0; i < screens.length; i++) {
      var screen = screens[i]
      if (screen && screen.name && screen.width > 0 && screen.height > 0) count += 1
    }

    return count
  }

  function hasRealScreen() {
    return realScreenCount() > 0
  }

  function queueSessionLock() {
    pendingSessionLock = true
    if (!sessionLockStabilizeTimer.running) logEvent("lock-pending: screen-stabilizing")
    sessionLockStabilizeTimer.restart()
    if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
  }

  function requestSessionLock() {
    if (!lockRequested || sessionLock.locked || sessionLock.secure) return
    if (sessionLockStabilizeTimer.running) return

    if (!hasRealScreen()) {
      if (!pendingSessionLock || lastEvent !== "lock-pending: no-real-screen") logEvent("lock-pending: no-real-screen")
      pendingSessionLock = true
      if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
      return
    }

    pendingSessionLock = false
    pendingSessionLockTimer.stop()
    sessionLock.locked = true
  }

  // ext-session-lock outlives its client, and a restart carries no lock over, so
  // a session locked this early is an orphan behind Hyprland's failsafe. Outputs
  // are often still absent here, so ask until the answer means something.
  function checkStrandedLock() {
    if (strandedLockResolved || strandedLockCheckProc.running) return

    // A lock this shell took is nobody's orphan.
    if (locked || lockRequested) {
      strandedLockResolved = true
      return
    }

    strandedLockCheckProc.running = true
  }

  function recoverStrandedLock() {
    if (!strandedLock || locked || !passwordPamConfigured) return

    strandedLock = false
    logEvent("lock-stranded: recovering")
    beginLock()
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function refreshFingerprintStatus() {
    if (!fingerprintCheckProc.running) fingerprintCheckProc.running = true
  }

  function logEvent(event) {
    lastEvent = event
    lastEventAt = new Date().toISOString()
    console.log("omarchy lock " + lastEventAt + " " + event)
  }

  function resetAuthenticationState() {
    enteredPassword = ""
    pendingPassword = ""
    failureMessage = ""
    failedAttempts = 0
    authenticatingPassword = false
    fingerprintAuthenticating = false
    fingerprintRetryTimer.stop()
    if (passwordPam.active) passwordPam.abort()
    if (fingerprintPam.active) fingerprintPam.abort()
  }

  function beginLock() {
    if (!passwordPamConfigured) {
      logEvent("lock-denied: missing-pam")
      return false
    }

    resetAuthenticationState()
    lockRequested = true
    keyboardBlanked = false
    keyboardOffSaved = false
    armBlankTimer()
    logEvent("lock-requested")
    queueSessionLock()

    Qt.callLater(function() {
      root.refreshBackground()
      root.refreshFingerprintStatus()
    })

    return true
  }

  function finishUnlock() {
    if (!root.locked && !lockRequested) return

    lockRequested = false
    pendingSessionLock = false
    sessionLockStabilizeTimer.stop()
    pendingSessionLockTimer.stop()
    resetAuthenticationState()
    idleBlankTimer.stop()
    sessionLock.locked = false
    logEvent("unlocked")
    runWake()
  }

  function armBlankTimer() {
    idleBlankTimer.armedAt = Date.now()
    idleBlankTimer.restart()
  }

  function runWake() {
    // A wake already in flight (e.g. from a keystroke nudge) must not cause
    // this request to vanish: queue a rerun so the display/keyboard restore
    // this call exists for still lands once the in-flight run finishes.
    if (!wakeProcess.running) wakeProcess.running = true
    else wakeRerunRequested = true
    if (lockRequested) armBlankTimer()
  }

  function runBlank() {
    // This is the real off, via brightnessctl's own save -- correct
    // regardless of whether a software or a hardware-driven change is what
    // the keyboard was showing, so the restore path below can prefer it over
    // the poll-tracked value once this has actually run.
    keyboardBlanked = true
    keyboardOffSaved = true
    if (!blankProcess.running) blankProcess.running = true
  }

  function submitPassword(value) {
    var password = String(value || "")
    if (!lockRequested || authenticatingPassword || password.length === 0) return

    runWake()
    pendingPassword = password
    failureMessage = ""
    authenticatingPassword = true

    if (!passwordPam.start()) {
      handlePasswordFailure()
      return
    }

    Qt.callLater(respondToPasswordPrompt)
  }

  function respondToPasswordPrompt() {
    if (!authenticatingPassword || !passwordPam.active || !passwordPam.responseRequired) return
    passwordPam.respond(pendingPassword)
  }

  function handlePasswordFailure() {
    if (!lockRequested) return

    authenticatingPassword = false
    enteredPassword = ""
    pendingPassword = ""
    failedAttempts += 1
    failureMessage = "Authentication failed (" + failedAttempts + ")"
    runWake()
  }

  function startFingerprint() {
    if (!lockRequested || !sessionLock.secure || !fingerprintConfigured) return
    if (fingerprintPam.active || fingerprintAuthenticating) return

    fingerprintAuthenticating = true
    if (!fingerprintPam.start()) {
      fingerprintAuthenticating = false
    }
  }

  function handleFingerprintFinished(result) {
    fingerprintAuthenticating = false

    if (!lockRequested) return
    if (result === PamResult.Success) {
      finishUnlock()
    } else if (fingerprintConfigured) {
      fingerprintRetryTimer.restart()
    }
  }

  WlSessionLock {
    id: sessionLock

    locked: false

    onSecureStateChanged: {
      root.logEvent("secure=" + secure)
      if (secure) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.startFingerprint()
      }
    }

    onLockStateChanged: {
      root.logEvent("session-locked=" + locked)

      if (locked) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
      }

      if (!locked && root.lockRequested) {
        root.lockRequested = false
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.resetAuthenticationState()
        root.runWake()
      }
    }

    WlSessionLockSurface {
      id: lockSurface
      color: Color.background

      LockView {
        id: lockView
        anchors.fill: parent
        backgroundPath: root.backgroundPath
        backgroundVersion: root.backgroundVersion
        fingerprintConfigured: root.fingerprintConfigured
        authenticatingPassword: root.authenticatingPassword
        failureMessage: root.failureMessage
        failedAttempts: root.failedAttempts
        inputEnabled: root.lockRequested
        loadBackground: root.locked
        passwordText: root.enteredPassword
        onPasswordTextEdited: function(password) { root.enteredPassword = password }
        onSubmitPassword: function(password) { root.submitPassword(password) }
        onClearFailureRequested: root.failureMessage = ""
        onWakeRequested: root.runWake()
      }

    }
  }

  PanelWindow {
    id: previewWindow
    visible: root.previewVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-lock-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    LockView {
      anchors.fill: parent
      backgroundPath: root.backgroundPath
      backgroundVersion: root.backgroundVersion
      fingerprintConfigured: root.fingerprintConfigured
      authenticatingPassword: false
      failureMessage: ""
      failedAttempts: 0
      inputEnabled: false
      loadBackground: root.previewVisible
      passwordText: ""
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: root.previewVisible = false
    }
  }

  PamContext {
    id: passwordPam
    config: "omarchy-lock-password"
    user: root.userName

    onResponseRequiredChanged: root.respondToPasswordPrompt()
    onPamMessage: root.respondToPasswordPrompt()

    onCompleted: function(result) {
      root.authenticatingPassword = false
      root.pendingPassword = ""

      if (!root.lockRequested) return
      if (result === PamResult.Success) root.finishUnlock()
      else root.handlePasswordFailure()
    }

    onError: function(error) {
      root.handlePasswordFailure()
    }
  }

  PamContext {
    id: fingerprintPam
    config: "omarchy-lock-fingerprint"
    user: root.userName

    onCompleted: function(result) {
      root.handleFingerprintFinished(result)
    }

    onError: function(error) {
      root.fingerprintAuthenticating = false
      if (root.lockRequested && root.fingerprintConfigured) fingerprintRetryTimer.restart()
    }
  }

  Timer {
    id: fingerprintRetryTimer
    interval: 250
    repeat: false
    onTriggered: root.startFingerprint()
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = String(text || "").trim()
        if (next !== root.backgroundPath) {
          root.backgroundPath = next
          root.backgroundVersion += 1
        }
      }
    }
  }

  Process {
    id: fingerprintCheckProc
    command: ["bash", "-c", "if [[ -f /etc/pam.d/omarchy-lock-fingerprint ]] && command -v fprintd-list >/dev/null 2>&1 && fprintd-list \"$USER\" 2>/dev/null | grep -qi finger; then echo yes; else echo no; fi"]
    stdout: StdioCollector { id: fingerprintCheckStdout; waitForEnd: true }
    onExited: {
      root.fingerprintConfigured = String(fingerprintCheckStdout.text || "").trim() === "yes"
      if (root.lockRequested && root.fingerprintConfigured) root.startFingerprint()
      else if (!root.fingerprintConfigured && fingerprintPam.active) fingerprintPam.abort()
    }
  }

  Process {
    id: strandedLockCheckProc
    command: ["bash", "-c", "omarchy-hyprland-session-locked"]
    onExited: function(exitCode) {
      // No output to read the lock off yet.
      if (exitCode === 2) return

      root.strandedLockResolved = true

      // A lock taken while this was in flight is this shell's own.
      root.strandedLock = exitCode === 0 && !root.locked && !root.lockRequested
      root.recoverStrandedLock()
    }
  }

  Process {
    id: wakeProcess
    // Keyboard restore only makes sense if this lock session actually blanked
    // it: otherwise it overwrites the user's current brightness (e.g. set via
    // a firmware-handled brightness key) with a stale value. When the real
    // off ran (keyboardOffSaved), brightnessctl's own restore is correct --
    // it saved whatever was actually current, software- or hardware-driven,
    // at that moment. Otherwise a suspend was merely detected without the
    // blank timer ever getting a turn, and the poll-tracked value is the
    // only thing that might still reflect what was showing beforehand.
    command: ["bash", "-c",
      "omarchy-brightness-display on" +
      (root.keyboardBlanked && root.kbdDeviceName
        ? (root.keyboardOffSaved
            ? "; omarchy-brightness-keyboard restore"
            : (root.savedKeyboardBrightness >= 0
                ? ("; brightnessctl -d '" + root.kbdDeviceName + "' set " + root.savedKeyboardBrightness)
                : ""))
        : "") +
      "; omarchy-hyprland-monitor-clamshell >/dev/null 2>&1 || true"]

    onExited: {
      if (!root.wakeRerunRequested) return
      root.wakeRerunRequested = false
      wakeProcess.running = true
    }
  }

  Process {
    id: blankProcess
    command: ["bash", "-c", "omarchy-brightness-keyboard off; omarchy-brightness-display off"]
  }

  Process {
    id: findKbdDeviceProc
    // Also reads the starting value: the watcher below only ever reports
    // changes, so without this, a session that locks before ever touching
    // the brightness key would have nothing to restore to. brightness_hw_changed
    // is itself optional -- only drivers that call
    // led_classdev_notify_brightness_hw_changed() expose it -- so check for it
    // rather than let the watcher loop forever opening a file that never exists.
    command: ["bash", "-c",
      "for c in /sys/class/leds/*kbd_backlight*; do [[ -e $c ]] && { " +
      "basename \"$c\"; cat \"$c/brightness\"; " +
      "[[ -e $c/brightness_hw_changed ]] && echo yes || echo no; break; }; done"]
    stdout: StdioCollector {
      id: findKbdDeviceStdout
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        var name = (lines[0] || "").trim()
        if (!name) return
        root.kbdDeviceName = name
        root.kbdBrightnessPath = "/sys/class/leds/" + name + "/brightness"
        var initial = parseInt((lines[1] || "").trim())
        if (!isNaN(initial)) root.savedKeyboardBrightness = initial
        if ((lines[2] || "").trim() === "yes") kbdWatcherProc.running = true
      }
    }
  }

  // The keyboard backlight can change outside any script the shell calls: a
  // firmware-handled brightness key changes the sysfs value directly, and on
  // some hardware the EC zeroes it the instant the lid shuts, before this
  // session even reacts to that -- either way, a value read only in response
  // is always too late; only one already on hand beforehand survives it. The
  // LED class exposes brightness_hw_changed exactly for this: a poll()-able
  // file the driver notifies on hardware-driven changes, so this can block
  // at zero cost until one actually happens rather than checking on a timer.
  Process {
    id: kbdWatcherProc
    // Before the first hardware-notified change since boot, the kernel has
    // nothing to report yet and reads raise ENODATA rather than returning
    // content -- an unrelated error still needs to surface, so only that one
    // is swallowed, on the priming read and after each wake alike.
    command: ["python3", "-u", "-c",
      "import select, errno\n" +
      "def drain(fh):\n" +
      "    try: fh.read()\n" +
      "    except OSError as e:\n" +
      "        if e.errno != errno.ENODATA: raise\n" +
      "f = open('" + root.kbdBrightnessPath.replace(/brightness$/, "brightness_hw_changed") + "')\n" +
      "drain(f); f.seek(0)\n" +
      "p = select.poll()\n" +
      "p.register(f, select.POLLPRI | select.POLLERR)\n" +
      "while True:\n" +
      "    if p.poll():\n" +
      "        f.seek(0); drain(f)\n" +
      "        print(open('" + root.kbdBrightnessPath + "').read().strip(), flush=True)\n"]
    stdout: SplitParser {
      onRead: function(line) {
        var val = parseInt(String(line).trim())
        if (isNaN(val)) return
        if (!root.kbdTrackingSuspended) root.savedKeyboardBrightness = val
      }
    }
    // This is meant to run for the shell's whole lifetime; if it ever exits
    // (crash, the sysfs path disappearing) restart it after a short delay
    // rather than silently going dark for the rest of the session.
    onExited: kbdWatcherRestartTimer.restart()
  }

  Timer {
    id: kbdWatcherRestartTimer
    interval: 2000
    repeat: false
    onTriggered: kbdWatcherProc.running = true
  }

  Timer {
    id: idleBlankTimer
    interval: 5000
    repeat: false
    property double armedAt: 0
    onTriggered: {
      // A countdown frozen by suspend fires right after resume, which would
      // blank the freshly woken unlock screen under the user. Wall-clock time
      // exposes the gap: take a fresh run-up instead of blanking.
      if (Date.now() - armedAt > interval + 2000) {
        // A real suspend happened here (that's what this gap means), and the
        // EC can reset the keyboard LED across suspend/resume on its own,
        // independent of whether this timer ever ran the blank. Let the next
        // wake restore it even though root never asked for the blank itself;
        // savedKeyboardBrightness has held the value from right before this
        // lock session started the whole time, untouched while locked.
        root.keyboardBlanked = true
        root.armBlankTimer()
        return
      }
      // Only a password check in flight should hold the display up. The
      // fingerprint PAM stays armed for the whole lock, so gating on
      // `authenticating` here would keep the panel lit until unlock.
      if (root.lockRequested && !root.authenticatingPassword) root.runBlank()
    }
  }

  Timer {
    id: sessionLockStabilizeTimer
    interval: 500
    repeat: false
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: pendingSessionLockTimer
    interval: 100
    repeat: true
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: strandedLockRetryTimer
    interval: 500
    repeat: true
    // Covers the compositor settling; screens coming back re-arm it.
    readonly property int budget: 20
    property int remaining: 20
    running: !root.strandedLockResolved && remaining > 0

    function rearm() {
      if (!root.strandedLockResolved) remaining = budget
    }

    onTriggered: {
      remaining -= 1
      root.checkStrandedLock()
    }
  }

  Connections {
    target: Quickshell
    function onScreensChanged() {
      root.requestSessionLock()

      // A monitor still coming up has no workspace, so cannot answer yet.
      strandedLockRetryTimer.rearm()
      root.checkStrandedLock()
    }
  }

  onAuthenticatingPasswordChanged: {
    if (!lockRequested) return
    if (authenticatingPassword) idleBlankTimer.stop()
    else armBlankTimer()
  }

  FileView {
    path: "/etc/pam.d/omarchy-lock-password"
    watchChanges: true
    printErrors: false
    onLoaded: root.passwordPamConfigured = true
    onLoadFailed: root.passwordPamConfigured = false
    onFileChanged: reload()
  }

  // No lock before PAM is known good. An answer from before then may be stale --
  // the failsafe can be cleared from a TTY -- so re-ask rather than act on it.
  onPasswordPamConfiguredChanged: {
    if (!passwordPamConfigured) return

    strandedLock = false
    strandedLockResolved = false
    strandedLockRetryTimer.rearm()
    checkStrandedLock()
  }

  Component.onCompleted: {
    refreshBackground()
    refreshFingerprintStatus()
    checkStrandedLock()
    findKbdDeviceProc.running = true
  }

  IpcHandler {
    target: "lock"

    function lock(): string {
      if (!root.passwordPamConfigured) return "missing-pam"
      if (!root.locked && !root.beginLock()) return "failed"
      return "ok"
    }

    function isLocked(): string {
      return root.locked ? "true" : "false"
    }

    function status(): string {
      return JSON.stringify({
        locked: root.locked,
        requested: root.lockRequested,
        pending: root.pendingSessionLock,
        sessionLocked: sessionLock.locked,
        secure: sessionLock.secure,
        realScreens: root.realScreenCount(),
        passwordPam: root.passwordPamConfigured,
        fingerprint: root.fingerprintConfigured,
        authenticating: root.authenticating,
        lastEvent: root.lastEvent,
        lastEventAt: root.lastEventAt
      })
    }

    function preview(): string {
      root.refreshBackground()
      root.refreshFingerprintStatus()
      root.previewVisible = true
      return "ok"
    }

    function hidePreview(): string {
      root.previewVisible = false
      return "ok"
    }
  }
}
