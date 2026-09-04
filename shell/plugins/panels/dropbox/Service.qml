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

  // --- Selective sync ---------------------------------------------------
  // `browsePath` is the folder currently on screen; "" means "follow the
  // account root", which is what we want before the first status lands.
  property string browsePath: ""
  property string folderParentPath: ""
  property bool folderAtRoot: true
  property var folders: []
  property string foldersError: ""
  property bool foldersLoaded: false

  // Optimistic desired state per folder, abs-path -> synced bool, in the same
  // spirit as `_desired` above: the switch throws the instant you click while
  // dropboxd spends its own sweet time resyncing. Entries are dropped once the
  // helper reports reality has caught up. QML does not signal on in-place
  // mutation, so every write reassigns the whole object.
  property var pendingFolders: ({})

  readonly property string effectiveBrowsePath: browsePath !== "" ? browsePath : accountPath

  function folderSynced(folder) {
    if (!folder) return false
    var pending = pendingFolders[String(folder.path || "")]
    if (pending !== undefined) return pending === true
    return folder.excluded !== true
  }

  function folderPending(folder) {
    if (!folder) return false
    return pendingFolders[String(folder.path || "")] !== undefined
  }

  function setPending(path, value) {
    var next = {}
    for (var key in pendingFolders) next[key] = pendingFolders[key]
    if (value === undefined) delete next[path]
    else next[path] = value
    pendingFolders = next
  }

  function loadFolders(path) {
    if (omarchyPath === "" || !authenticated) return
    var target = String(path || effectiveBrowsePath || accountPath || "")
    if (target === "") return
    // Only one listing runs at a time, but a request that arrives mid-flight
    // must not be dropped: the in-flight result would then apply its own (now
    // stale) path over the one just asked for. Remember it and run it on exit.
    if (foldersProcess.running) {
      _queuedFolderPath = target
      return
    }
    _queuedFolderPath = ""
    _foldersOutput = ""
    _foldersError = ""
    foldersProcess.command = ["python3", foldersHelperPath, "list", target]
    foldersProcess.running = true
  }

  function applyFolders(raw) {
    var parsed = Model.parseFolders(raw)
    if (parsed.ok !== true) {
      foldersError = elideStatus(parsed.error || "Could not read Dropbox folders")
      folders = []
      foldersLoaded = true
      return
    }
    foldersError = ""
    browsePath = String(parsed.path || "")
    folderParentPath = String(parsed.parentPath || "")
    folderAtRoot = parsed.atRoot === true
    var rows = parsed.folders || []
    folders = rows.length > maxFolderRows ? rows.slice(0, maxFolderRows) : rows

    // Reality caught up for any folder whose real state now matches what was
    // asked for — stop overriding it.
    var next = {}
    var settled = {}
    for (var i = 0; i < folders.length; i++) settled[folders[i].path] = folders[i].excluded !== true
    for (var key in pendingFolders) {
      if (settled[key] === undefined || settled[key] !== pendingFolders[key]) next[key] = pendingFolders[key]
    }
    pendingFolders = next
    foldersLoaded = true
  }

  function resetBrowse() {
    browsePath = ""
    loadFolders(accountPath)
  }

  function enterFolder(folder) {
    if (!folder || folder.browsable !== true) return
    loadFolders(String(folder.path || ""))
  }

  function goUpFolder() {
    if (folderAtRoot || folderParentPath === "") return
    loadFolders(folderParentPath)
  }

  function setFolderSynced(folder, on) {
    if (!folder || !installed || excludeProcess.running) return
    var path = String(folder.path || "")
    if (path === "") return
    setPending(path, on === true)
    _excludePath = path
    _excludeOutput = ""
    _excludeError = ""
    excludeProcess.command = ["dropbox-cli", "exclude", on ? "remove" : "add", path]
    excludeProcess.running = true
  }

  function toggleFolderSynced(folder) {
    if (!folder) return
    setFolderSynced(folder, !folderSynced(folder))
  }

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 60, 10, 3600)
  readonly property int maxFolderRows: intSetting("maxFolderRows", 50, 10, 500)
  readonly property bool busy: statusProcess.running || loginProcess.running || controlProcess.running
  // Two different kinds of busy. `foldersBusy` covers the read-only listing and
  // only gates the refresh button. `syncBusy` is an actual exclude add/remove in
  // flight — the one thing that genuinely cannot overlap. Gating toggles on the
  // listing instead would silently swallow clicks for the ~10s the settle timer
  // spends re-polling, which is exactly when someone wants to undo.
  readonly property bool foldersBusy: foldersProcess.running || excludeProcess.running
  readonly property bool syncBusy: excludeProcess.running

  readonly property string pluginPath: (omarchyPath || "") + "/shell/plugins/panels/dropbox"
  readonly property string helperPath: pluginPath + "/status.py"
  readonly property string foldersHelperPath: pluginPath + "/folders.py"

  property string _statusOutput: ""
  property string _statusError: ""
  property string _loginOutput: ""
  property string _loginError: ""
  property bool _loginUrlOpened: false
  property string _controlOutput: ""
  property string _controlError: ""
  property string _foldersOutput: ""
  property string _foldersError: ""
  property string _excludeOutput: ""
  property string _excludeError: ""
  property string _excludePath: ""
  property string _queuedFolderPath: ""

  onAuthenticatedChanged: {
    if (authenticated) {
      loadFolders()
    } else {
      browsePath = ""
      folders = []
      foldersError = ""
      foldersLoaded = false
      pendingFolders = ({})
      _queuedFolderPath = ""
    }
  }

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
    if (statusProcess.running || omarchyPath === "") return
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
    // Before `authenticated`, whose change handler loads the folder list and
    // needs somewhere to load it from. Assigning it after left that first load
    // with an empty account path, so it silently did nothing.
    accountPath = String(parsed.accountPath || "")
    authenticated = parsed.authenticated === true
    // Reality caught up to the pending pause/resume — stop overriding.
    if (_desired !== -1 && running === (_desired === 1)) _desired = -1
    statusText = String(parsed.statusText || (installed ? "Stopped" : "Not installed"))
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
    // After a fresh boot the startup poll usually lands before dropboxd has
    // finished its respawn dance, which left the icon stale until the next
    // periodic refresh. Poll quickly until the daemon shows up, or give up
    // after ~30 seconds.
    id: startupRamp
    property int ticks: 0
    interval: 2000
    repeat: true
    running: true
    onTriggered: {
      ticks += 1
      if (root.running || ticks >= 15) startupRamp.running = false
      else root.refresh()
    }
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

  Timer {
    // An exclude add/remove returns as soon as the daemon accepts it, but the
    // folder does not appear or vanish on disk until the resync lands. Re-poll
    // a handful of times so the row settles without waiting on the periodic
    // refresh; anything still pending after that keeps its optimistic value
    // until the next successful load.
    id: folderSettleTimer
    property int ticks: 0
    interval: 2000
    repeat: true
    running: false
    onTriggered: {
      folderSettleTimer.ticks += 1
      root.loadFolders()
      if (folderSettleTimer.ticks >= 5) {
        folderSettleTimer.ticks = 0
        folderSettleTimer.running = false
      }
    }
  }

  Process {
    id: foldersProcess
    running: false
    command: []
    stdout: StdioCollector { id: foldersStdout; waitForEnd: true; onStreamFinished: root._foldersOutput = text }
    stderr: StdioCollector { id: foldersStderr; waitForEnd: true; onStreamFinished: root._foldersError = text }
    onExited: function(exitCode) {
      var stdout = String(foldersStdout.text || root._foldersOutput || "")
      var stderr = String(foldersStderr.text || root._foldersError || "")
      // A newer request came in while this one was running, so this result is
      // already stale — drop it rather than let it apply its path, and serve
      // the request that superseded it.
      if (root._queuedFolderPath !== "") {
        var queued = root._queuedFolderPath
        root._queuedFolderPath = ""
        root.loadFolders(queued)
        return
      }
      if (exitCode === 0 && stdout !== "") root.applyFolders(stdout)
      else {
        root.foldersError = root.elideStatus(stderr || stdout || "Could not read Dropbox folders")
        root.foldersLoaded = true
      }
    }
  }

  Process {
    id: excludeProcess
    running: false
    command: []
    stdout: StdioCollector { id: excludeStdout; waitForEnd: true; onStreamFinished: root._excludeOutput = text }
    stderr: StdioCollector { id: excludeStderr; waitForEnd: true; onStreamFinished: root._excludeError = text }
    onExited: function(exitCode) {
      var stdout = String(excludeStdout.text || root._excludeOutput || "")
      var stderr = String(excludeStderr.text || root._excludeError || "")
      // The CLI reports "Dropbox isn't running!" on stdout with exit 0, so the
      // exit code alone is not enough to call this a success.
      var combined = stdout + " " + stderr
      var failed = exitCode !== 0 || /isn't running|isn't responding|Couldn't |daemon stopped/i.test(combined)
      if (failed) {
        // Drop only this folder's optimistic value; other folders may still
        // have legitimate pending state from earlier toggles.
        root.setPending(root._excludePath, undefined)
        root.lastError = root.elideStatus(stderr || stdout || "Could not change folder syncing")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
      }
      folderSettleTimer.ticks = 0
      folderSettleTimer.restart()
      root.loadFolders()
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
