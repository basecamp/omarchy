import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  visible: false

  property var accounts: []
  property var current: null
  property var live: null
  property string errorText: ""
  property bool switching: false
  property bool ready: false

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string indexPath: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state")
    + "/omarchy/agent-accounts/claude/index.json"
  readonly property string currentId: current && current.id ? String(current.id) : ""
  readonly property string currentEmail: current && current.email ? String(current.email) : ""
  readonly property string liveId: live && live.id ? String(live.id) : ""

  signal switched()

  FileView {
    path: root.indexPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyIndex(text())
    onLoadFailed: if (!root.ready) root.sync()
  }

  Process {
    id: listProcess
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyIndex(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") root.errorText = text.trim()
    }
  }

  Process {
    id: useProcess
    running: false
    onExited: {
      root.switching = false
      root.sync()
      root.switched()
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") root.errorText = text.trim()
    }
  }

  function applyIndex(raw) {
    var parsed
    try { parsed = JSON.parse(String(raw || "")) } catch (e) { parsed = null }
    if (!parsed || typeof parsed !== "object") return
    var rows = Array.isArray(parsed.accounts) ? parsed.accounts : []
    var activeId = String(parsed.activeId || (parsed.current && parsed.current.id) || "")
    var out = []
    var seen = {}
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i] || {}
      var id = String(row.id || "")
      if (id === "" || seen[id]) continue
      seen[id] = true
      var active = row.active === true || (activeId !== "" && id === activeId)
      out.push({
        id: id,
        email: String(row.email || row.label || id),
        label: String(row.email || row.label || id),
        plan: String(row.plan || ""),
        organization: String(row.organization || ""),
        active: active
      })
    }
    root.accounts = out
    var selected = out.filter(function(item) { return item.active })[0] || null
    root.current = selected
    root.live = parsed.live && typeof parsed.live === "object" ? parsed.live : null
    root.ready = true
    root.errorText = ""
  }

  function sync() {
    if (listProcess.running) return
    listProcess.command = ["omarchy-agent-account", "list", "--json"]
    listProcess.running = true
  }

  function use(id) {
    var accountId = String(id || "")
    if (accountId === "" || root.switching) return
    if (root.currentId === accountId && root.liveId === accountId) return
    root.switching = true
    root.errorText = ""
    useProcess.command = ["omarchy-agent-account", "use", "claude", accountId]
    useProcess.running = true
  }

  function addAccount() {
    Quickshell.execDetached([
      "bash", "-lc",
      "omarchy-shell -q omarchy.agents close; sleep 0.2; exec omarchy-launch-tui --app-id=TUI.float omarchy-agent-account add claude"
    ])
  }

  Component.onCompleted: sync()
}
