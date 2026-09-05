import QtQuick
import qs.Ui

BarIndicator {
  id: root

  readonly property var dictationService: bar?.shell?.firstPartyServiceFor("omarchy.dictation")
  property string state: dictationService ? dictationService.dictationState : "idle"
  readonly property string icon: state === "recording" ? "󰍬" : state === "transcribing" ? "󰔟" : ""

  active: state === "recording"
  activeText: icon
  inactiveText: "󰍬"
  activeTooltipText: state
  inactiveTooltipText: "Dictate"

  onPressed: function() {
    if (!root.bar) return
    root.bar.run("omarchy-voxtype-config")
  }
}
