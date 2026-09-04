import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var notifications: []
  property var issues: []
  property var pullRequests: []
  property var discussions: []
  property var ci: []
  property string viewer: ""
  property string fetchedAt: ""
  property string lastError: ""
  property string errorKind: ""
  property bool partial: false
  property bool stale: false
  property bool refreshing: false
  property bool refreshPending: false

  readonly property string helperPath: (omarchyPath || "") + "/shell/plugins/panels/github/github_client.py"
  readonly property int attentionCount: notifications.length + issues.length + reviewRequestCount + failingCiCount
  readonly property int reviewRequestCount: countWhere(pullRequests, "lane", "Review requested")
  readonly property int failingCiCount: countWhere(ci, "state", "FAILURE") + countWhere(ci, "state", "ERROR")

  function countWhere(items, key, value) {
    var count = 0
    for (var i = 0; i < items.length; i++) if (String(items[i][key] || "") === value) count++
    return count
  }

  function refresh() {
    if (fetchProcess.running) {
      refreshPending = true
      return
    }
    if (helperPath === "/shell/plugins/panels/github/github_client.py") return
    refreshing = true
    lastError = ""
    fetchProcess.running = true
  }

  function applyResult(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (!parsed || parsed.ok !== true) {
        errorKind = String(parsed && parsed.errorKind || "fetch")
        lastError = String(parsed && parsed.error || "GitHub could not be refreshed")
        stale = parsed && parsed.stale === true
        return
      }
      viewer = String(parsed.viewer || "")
      notifications = Array.isArray(parsed.notifications) ? parsed.notifications : []
      issues = Array.isArray(parsed.issues) ? parsed.issues : []
      pullRequests = Array.isArray(parsed.pullRequests) ? parsed.pullRequests : []
      discussions = Array.isArray(parsed.discussions) ? parsed.discussions : []
      ci = Array.isArray(parsed.ci) ? parsed.ci : []
      fetchedAt = String(parsed.fetchedAt || "")
      partial = parsed.partial === true
      stale = parsed.stale === true
      errorKind = ""
      lastError = String(parsed.error || "")
    } catch (error) {
      errorKind = "parse"
      lastError = "GitHub returned an unreadable response"
    }
  }

  Process {
    id: fetchProcess
    command: ["python3", root.helperPath]
    running: false
    stdout: StdioCollector {
      id: fetchStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: fetchStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.refreshing = false
      if (fetchStdout.text) root.applyResult(fetchStdout.text)
      else {
        root.errorKind = "process"
        root.lastError = root.shortError(fetchStderr.text || "GitHub helper did not return data")
      }
      if (root.refreshPending) {
        root.refreshPending = false
        root.refresh()
      }
    }
  }

  function shortError(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 180 ? value.substring(0, 177) + "…" : value
  }

  Timer {
    interval: 180000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: refresh()
}
