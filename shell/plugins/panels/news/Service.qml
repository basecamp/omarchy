import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var settings: ({})
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var items: []
  property var sources: []
  property var lastSeenBySource: ({})
  property string fetchedAt: ""
  property string lastError: ""
  property bool stale: false
  property bool partial: false
  property bool refreshing: false
  property bool stateLoaded: false

  readonly property string helperPath: (omarchyPath || "") + "/shell/plugins/panels/news/fetch_news.py"
  readonly property string stateRoot: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
  readonly property string stateDir: stateRoot + "/omarchy/news"
  readonly property string statePath: stateDir + "/read.json"
  readonly property int refreshIntervalMin: intSetting("refreshIntervalMin", 15, 5, 120)
  readonly property int itemLimit: intSetting("itemLimit", 10, 5, 20)
  readonly property string feedPack: String(setting("feedPack", "Omarchy only"))
  readonly property var enabledSourceIds: feedPack === "Omarchy + Tech top 10"
    ? ["omarchy", "hacker-news", "ars-technica", "techcrunch", "the-verge", "wired", "phoronix", "its-foss", "openai-news", "hugging-face", "mit-ai"]
    : ["omarchy"]
  readonly property var visibleItems: items.slice(0, itemLimit)
  readonly property int unreadCount: countUnread()

  onFeedPackChanged: if (stateLoaded) refresh()

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
    if (!stateLoaded || items.length === 0) return 0
    var total = 0
    for (var sourceIndex = 0; sourceIndex < sources.length; sourceIndex++) {
      var sourceId = String(sources[sourceIndex].id || "")
      var lastSeenId = String(lastSeenBySource[sourceId] || "")
      if (lastSeenId === "") continue
      var sourceItems = itemsForSource(sourceId)
      var found = false
      for (var i = 0; i < sourceItems.length; i++) {
        if (String(sourceItems[i].id || "") === lastSeenId) {
          total += i
          found = true
          break
        }
      }
      if (!found) total += Math.min(sourceItems.length, itemLimit)
    }
    return total
  }

  function itemsForSource(sourceId) {
    if (!sourceId || sourceId === "all") return items.slice(0, itemLimit)
    var filtered = []
    for (var i = 0; i < items.length && filtered.length < itemLimit; i++) {
      if (String(items[i].sourceId || "") === sourceId) filtered.push(items[i])
    }
    return filtered
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
      sources = Array.isArray(parsed.sources) ? parsed.sources : []
      fetchedAt = String(parsed.fetchedAt || "")
      stale = parsed.stale === true
      partial = parsed.partial === true
      lastError = String(parsed.error || "")
    } catch (error) {
      lastError = "Could not read the Omarchy news feed"
    }
  }

  function markAllSeen() {
    if (items.length === 0) return
    var next = ({})
    var marked = ({})
    for (var key in lastSeenBySource) next[key] = lastSeenBySource[key]
    for (var i = 0; i < items.length; i++) {
      var sourceId = String(items[i].sourceId || "omarchy")
      if (!marked[sourceId]) {
        next[sourceId] = String(items[i].id || "")
        marked[sourceId] = true
      }
    }
    lastSeenBySource = next
    readState.setText(JSON.stringify({ version: 2, lastSeenBySource: next }, null, 2) + "\n")
  }

  function loadReadState(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (parsed.lastSeenBySource && typeof parsed.lastSeenBySource === "object") {
        lastSeenBySource = parsed.lastSeenBySource
      } else if (parsed.lastSeenId) {
        var legacyId = String(parsed.lastSeenId)
        lastSeenBySource = ({ "omarchy": legacyId.indexOf("omarchy:") === 0 ? legacyId : "omarchy:" + legacyId })
      } else {
        lastSeenBySource = ({})
      }
    } catch (error) {
      lastSeenBySource = ({})
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
    command: ["mkdir", "-p", root.stateDir]
    running: true
    onExited: function() {
      readState.reload()
      root.refresh()
    }
  }

  Process {
    id: fetchProcess
    command: ["python3", root.helperPath, "--sources", root.enabledSourceIds.join(",")]
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
