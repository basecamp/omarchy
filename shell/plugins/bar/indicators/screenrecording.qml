import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

BarIndicator {
  id: root

  property string statusText: ""
  property string statusTooltip: ""

  active: statusText !== ""
  activeText: statusText
  inactiveText: "󰻂"
  activeTooltipText: statusTooltip
  inactiveTooltipText: "Screen recording"

  function refresh() {
    if (!root.bar || statusProc.running) return
    statusProc.command = ["bash", "-lc", Util.shellQuote(root.bar.omarchyPath + "/shell/scripts/indicators/screen-recording.sh")]
    statusProc.running = true
  }

  function update(raw) {
    var data = extractData(raw)

    statusText = data.text || ""
    statusTooltip = data.tooltip || ""
  }

  onBarChanged: refresh()
  Component.onCompleted: refresh()

  Connections {
    target: root.bar
    ignoreUnknownSignals: true
    function onIndicatorsRefreshRequested() { root.refresh() }
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.update(text)
    }
  }

  onPressed: function() {
    if (root.bar) root.bar.run("omarchy-capture-screenrecording")
  }
}
