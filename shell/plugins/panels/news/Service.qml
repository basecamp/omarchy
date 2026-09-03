import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var settings: ({})
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var items: []
  property string lastSeenId: ""
  property string fetchedAt: ""
  property string lastError: ""
  property bool stale: false
  property bool refreshing: false
  property bool stateLoaded: false

  readonly property string helperPath: (omarchyPath || "") + "/shell/plugins/panels/news/fetch_news.py"
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/news/read.json"
  readonly property int refreshIntervalMin: intSetting("refreshIntervalMin", 15, 5, 120)
  readonly property int itemLimit: intSetting("itemLimit", 10, 5, 20)
  readonly property var visibleItems: items.slice(0, itemLimit)
  readonly property int unreadCount: countUnread()

  property string _stdout: ""
  property string _stderr: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(min, Math.min(max, value))
  }

  function countUnread() {
    if (!stateLoaded || lastSeenId === "" || items.length === 0) return 0
    for (var i = 0; i < items.length; i++) {
      if (String(items[i].id || "") === lastSeenId) return i
    }
    return Math.min(items.length, itemLimit)
  }

  function refresh() {
    if (fetchProcess.running || helperPath === "/shell/plugins/panels/news/fetch_news.py") return
    _stdout = ""
    _stderr = ""
    refreshing = true
    fetchProcess.running = true
  }

  function applyResult(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (!parsed || parsed.ok !== true || !Array.isArray(parsed.items)) throw new Error("invalid result")
      items = parsed.items
      fetchedAt = String(parsed.fetchedAt || "")
      stale = parsed.stale === true
      lastError = String(parsed.error || "")
    } catch (error) {
      lastError = "Could not read the Omarchy news feed"
    }
  }

  function markAllSeen() {
    if (items.length === 0) return
    lastSeenId = String(items[0].id || "")
    if (lastSeenId !== "") {
      readState.setText(JSON.stringify({ version: 1, lastSeenId: lastSeenId }, null, 2) + "\n")
    }
  }

  function loadReadState(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      lastSeenId = String(parsed.lastSeenId || "")
    } catch (error) {
      lastSeenId = ""
    }
    stateLoaded = true
  }

  function shortError(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 180 ? value.substring(0, 177) + "…" : value
  }

  FileView {
    id: readState
    path: root.statePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadReadState(text())
    onLoadFailed: root.stateLoaded = true
  }

  Process {
    id: prepareState
    command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/omarchy/news"]
    running: true
    onExited: function() {
      readState.reload()
      root.refresh()
    }
  }

  Process {
    id: fetchProcess
    command: ["python3", root.helperPath]
    running: false
    stdout: StdioCollector {
      id: fetchStdout
      waitForEnd: true
      onStreamFinished: root._stdout = text
    }
    stderr: StdioCollector {
      id: fetchStderr
      waitForEnd: true
      onStreamFinished: root._stderr = text
    }
    onExited: function(exitCode) {
      root.refreshing = false
      var output = String(fetchStdout.text || root._stdout || "")
      var error = String(fetchStderr.text || root._stderr || "")
      if (output.trim() !== "") root.applyResult(output)
      else if (exitCode !== 0) root.lastError = root.shortError(error || "Could not fetch Omarchy news")
    }
  }

  Timer {
    interval: root.refreshIntervalMin * 60 * 1000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }
}
