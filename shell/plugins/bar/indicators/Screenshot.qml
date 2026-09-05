import QtQuick
import qs.Ui

BarIndicator {
  id: root

  active: false
  activeText: ""
  inactiveText: ""
  activeTooltipText: "Copy Region Screenshot"
  inactiveTooltipText: "Copy Region Screenshot"

  onPressed: function() {
    if (root.bar) {
      root.bar.run("omarchy-capture-screenshot region copy")
    }
  }
}
