import QtQuick
import qs.Commons
import qs.Ui

BarIndicator {
  id: root

  readonly property var notificationService: bar.shell.firstPartyServiceFor("omarchy.notifications")
  readonly property bool dnd: notificationService ? notificationService.doNotDisturb : false

  active: dnd
  activeText: "󰂛"
  inactiveText: "󰂛"
  activeTooltipText: "Notifications silenced"
  inactiveTooltipText: "Do Not Disturb"

  onPressed: function() {
    if (root.notificationService) {
      root.notificationService.setDoNotDisturb(!root.notificationService.doNotDisturb)
    }
  }
}
