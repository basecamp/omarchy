import QtQuick
import Quickshell.Io
import qs.Ui

BarIndicator {
  id: root

  property string mode: "idle"
  property string icon: ""

  active: mode === "recording"
  activeText: icon
  inactiveText: "󰍬"
  activeTooltipText: mode
  inactiveTooltipText: "Dictate"

  function update(raw) {
    var data = extractData(raw)

    mode = String(data.alt || data.class || "idle")
    if (mode === "recording") icon = "󰍬"
    else if (mode === "transcribing") icon = "󰔟"
    else icon = ""
  }

  Process {
    command: ["bash", "-c", "omarchy-voxtype-status"]
    running: true
    stdout: SplitParser {
      onRead: function(data) { root.update(data) }
    }
  }

  onPressed: function() {
    if (!root.bar) return
    root.bar.run("omarchy-voxtype-config")
  }
}
