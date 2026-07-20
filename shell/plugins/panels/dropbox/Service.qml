import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  property bool installed: false
  property bool running: false
  property bool authenticated: false

  // Optimistic sync state so the UI reacts the instant you click, rather than
  // waiting for dropboxd to actually settle. _desired is -1 while we just
  // follow the real state, or 0/1 while a pause/resume is still catching up.
  property int _desired: -1
  readonly property bool active: _desired === -1 ? running : (_desired === 1)
  property bool refreshing: false
  property string statusText: "Checking…"
  property string accountPath: ""
  property string plan: ""
  property double usedBytes: 0
  property double quotaBytes: 0
  property double usagePercent: 0
  property bool quotaKnown: false
  property var files: []
  property string actionStatus: ""
  property string lastError: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 60, 10, 3600)
  readonly property bool busy: statusProcess.running || loginProcess.running || controlProcess.running
  readonly property string helperPath: (omarchyPath || "") + "/shell/plugins/panels/dropbox/status.py"

  property string _statusOutput: ""
  property string _statusError: ""
  property string _loginOutput: ""
  property string _loginError: ""
  property bool _loginUrlOpened: false
  property string _controlOutput: ""
  property string _controlError: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function refresh() {
    if (statusProcess.running || helperPath === "/shell/plugins/panels/dropbox/status.py") return
    _statusOutput = ""
    _statusError = ""
    refreshing = true
    statusProcess.command = ["python3", helperPath, "25"]
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      lastError = parsed.lastError || "Failed to read Dropbox status"
      return
    }
    installed = parsed.installed === true
    running = parsed.running === true
    authenticated = parsed.authenticated === true
    // Reality caught up to the pending pause/resume — stop overriding.
    if (_desired !== -1 && running === (_desired === 1)) _desired = -1
    statusText = String(parsed.statusText || (installed ? "Stopped" : "Not installed"))
    accountPath = String(parsed.accountPath || "")
    plan = String(parsed.plan || "")
    usedBytes = Number(parsed.usedBytes || 0)
    quotaBytes = Number(parsed.quotaBytes || 0)
    usagePercent = Number(parsed.usagePercent || 0)
    quotaKnown = parsed.quotaKnown === true
    files = parsed.files || []
    lastError = ""
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  function login() {
    if (!installed || loginProcess.running) return
    _loginOutput = ""
    _loginError = ""
    _loginUrlOpened = false
    actionStatus = "Starting Dropbox login…"
    loginProcess.command = ["dropbox-cli", "start"]
    loginProcess.running = true
  }

  function pause() {
    runControl(["dropbox-cli", "stop"], 0)
  }

  function resume() {
    runControl(["dropbox-cli", "start"], 1)
  }

  function toggleRunning() {
    if (active) pause()
    else resume()
  }

  function runControl(command, desired) {
    // No progress status here — the greyed icon and hero phrase already convey
    // the pause/resume; only surface a message if the command fails.
    if (!installed || controlProcess.running) return
    _desired = desired
    _controlOutput = ""
    _controlError = ""
    controlProcess.command = command
    controlProcess.running = true
  }

  function openFile(file) {
    if (!file || !file.path) return
    Quickshell.execDetached(["uwsm-app", "--", "nautilus", "--select", fileUri(String(file.path))])
  }

  function fileUri(path) {
    var parts = String(path || "").split("/")
    for (var i = 0; i < parts.length; i++) parts[i] = encodeURIComponent(parts[i])
    return "file://" + parts.join("/")
  }

  function openAuthUrlFrom(text) {
    if (_loginUrlOpened) return true
    var match = String(text || "").match(/https?:\/\/\S+/)
    if (match && match[0]) {
      _loginUrlOpened = true
      Qt.openUrlExternally(match[0])
      actionStatus = "Opened Dropbox login"
      actionStatusTimer.restart()
      return true
    }
    return false
  }

  function handleLoginOutput(data, isError) {
    var text = String(data || "")
    if (isError) _loginError += text + "\n"
    else _loginOutput += text + "\n"
    openAuthUrlFrom(text)
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: delayedRefresh
    interval: 1000
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    // dropboxd takes a few (variable) seconds to settle after stop/start, so
    // re-poll a handful of times to reflect the new state without waiting for
    // the next periodic refresh.
    id: settleTimer
    property int ticks: 0
    interval: 1500
    repeat: true
    running: false
    onTriggered: {
      settleTimer.ticks += 1
      root.refresh()
      if (settleTimer.ticks >= 4) {
        settleTimer.ticks = 0
        settleTimer.running = false
        root._desired = -1
      }
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) root.applyStatus(stdout)
      else root.lastError = root.elideStatus(stderr || stdout || "Could not read Dropbox status")
    }
  }

  Process {
    id: loginProcess
    running: false
    command: []
    stdout: SplitParser { onRead: function(data) { root.handleLoginOutput(data, false) } }
    stderr: SplitParser { onRead: function(data) { root.handleLoginOutput(data, true) } }
    onExited: function(exitCode) {
      var combined = String(root._loginOutput || "") + "\n" + String(root._loginError || "")
      var opened = root.openAuthUrlFrom(combined)
      if (exitCode !== 0 && !opened) {
        root.lastError = root.elideStatus(combined || "Dropbox login failed")
        root.actionStatus = root.lastError
      } else if (!opened) {
        root.actionStatus = ""
        root.lastError = ""
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: controlProcess
    running: false
    command: []
    stdout: StdioCollector { id: controlStdout; waitForEnd: true; onStreamFinished: root._controlOutput = text }
    stderr: StdioCollector { id: controlStderr; waitForEnd: true; onStreamFinished: root._controlError = text }
    onExited: function(exitCode) {
      var stdout = String(controlStdout.text || root._controlOutput || "")
      var stderr = String(controlStderr.text || root._controlError || "")
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = root.elideStatus(stderr || stdout || "Dropbox command failed")
        root.actionStatus = root.lastError
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      settleTimer.ticks = 0
      settleTimer.restart()
      delayedRefresh.restart()
    }
  }
}
