import QtQuick
import qs.Ui

BarIndicator {
  id: root

  readonly property var dictationService: bar?.shell?.firstPartyServiceFor("omarchy.voxtype")
  readonly property string state: dictationService ? dictationService.state : "idle"
  readonly property string icon: state === "transcribing" ? "󰔟" : "󰍬"

  active: dictationService ? dictationService.busy : false
  activeText: icon
  inactiveText: "󰍬"
  activeTooltipText: state
  inactiveTooltipText: "Dictate"

  onPressed: function() {
    if (!root.bar) return
    root.bar.run("omarchy-voxtype-config")
  }
}
