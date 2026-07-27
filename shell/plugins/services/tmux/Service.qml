import QtQuick
import Quickshell.Io
import "TmuxModel.js" as TmuxModel

Item {
  id: root

  // Injected by omarchy-shell (the first-party service loader).
  property var shell: null

  property int waitingCount: 0
  property string tooltip: ""
  property bool refreshPending: false

  readonly property bool waiting: waitingCount > 0

  // A bar surface exists per monitor and each one instantiates the indicator
  // twice (active and inactive block), so the probe lives here instead: one
  // process for the whole shell, and every indicator reads the same answer.
  function refresh() {
    if (statusProc.running) refreshPending = true
    else statusProc.running = true
  }

  // tmux hooks cover the flag transitions, but output in a selected window
  // whose terminal sits on another workspace never fires one, and neither does
  // a window or session killed while it was still flagged.
  Timer {
    interval: 3000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    command: ["omarchy-tmux-alert", "show", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var waiting = TmuxModel.waitingFromOutput(text)
        root.waitingCount = waiting.count
        root.tooltip = waiting.tooltip
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.waitingCount = 0
        root.tooltip = ""
      }

      if (root.refreshPending) {
        root.refreshPending = false
        root.refresh()
      }
    }
  }

  Component.onCompleted: refresh()
}
