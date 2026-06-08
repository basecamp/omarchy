import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarIndicator {
  id: root

  property int reminderCount: 0
  property string tooltip: ""

  active: reminderCount > 0
  activeText: "󰢌"
  inactiveText: "󰢌"
  activeTooltipText: tooltip
  inactiveTooltipText: tooltip

  function refresh() {
    if (!jsonProc.running) jsonProc.running = true
  }

  function openReminderFlow() {
    Quickshell.execDetached(["omarchy-reminder", "-i"])
  }

  function update(raw) {
    var data = extractData(raw)
    reminderCount = Number(data.count || 0)
    tooltip = String(data.tooltip || "")
  }

  Component.onCompleted: refresh()

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() { root.refresh() }
  }

  Process {
    id: jsonProc
    command: ["omarchy-reminder", "show", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.update(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.reminderCount = 0
        root.tooltip = ""
      }
    }
  }

  onPressed: function() {
    if (root.reminderCount > 0) Quickshell.execDetached(["omarchy-reminder", "show"])
    else root.openReminderFlow()
  }
}
