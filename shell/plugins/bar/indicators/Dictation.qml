import QtQuick
import Quickshell.Io
import qs.Ui

BarIndicator {
  id: root

  property string state: "idle"
  property string icon: ""

  active: state === "recording"
  activeText: icon
  inactiveText: "󰍬"
  activeTooltipText: state
  inactiveTooltipText: "Dictate"

  function update(raw) {
    var data = extractData(raw)

    state = String(data.alt || data.class || "idle")
    if (state === "recording") icon = "󰍬"
    else if (state === "transcribing") icon = "󰔟"
    else icon = ""
  }

  Process {
    command: ["bash", "-c", "omarchy-voxtype-status"]
    running: true
    stdout: SplitParser {
      onRead: function(data) { root.update(data) }
    }
  }

  onPressed: function(button) {
    if (!root.bar) return
    // Left click toggles dictation, matching the SUPER+CTRL+X binding and the
    // toggle-on-click behavior of every sibling indicator. Any other button
    // opens the Voxtype config TUI.
    if (button === Qt.LeftButton) root.bar.run("voxtype record toggle")
    else root.bar.run("omarchy-voxtype-config")
  }
}
