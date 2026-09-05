import QtQuick
import Quickshell.Io

// One agent's usage record, read straight off the data file that
// omarchy-agent-usage-update maintains. The panel never learns how the
// numbers were made — a record that appears in the usage directory is an
// agent, whoever wrote it.
Item {
  id: root
  visible: false

  property string agentId: ""
  property string path: ""
  property var record: null

  FileView {
    id: agentFile
    path: root.path
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parse(text())
    onLoadFailed: root.record = null
  }

  // Fallback reload when inotify watch-rearms fail (quota exhaustion, ENOSPC).
  // The atomic mv rewrite replaces the inode; if inotify can't re-arm, the
  // FileView stays frozen. Periodic reload bounds staleness (#9974).
  Timer {
    interval: 120000
    repeat: true
    running: true
    onTriggered: agentFile.reload()
  }

  function parse(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      root.record = parsed && typeof parsed === "object" ? parsed : null
    } catch (e) {
      console.warn("agents", "Ignoring bad usage record", root.path, e)
      root.record = null
    }
  }
}
