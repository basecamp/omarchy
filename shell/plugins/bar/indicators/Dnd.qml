import QtQuick
import qs.Commons
import qs.Ui

BarIndicator {
  id: root

  readonly property var notificationService: bar && bar.shell && typeof bar.shell.firstPartyServiceFor === "function"
    ? bar.shell.firstPartyServiceFor("omarchy.notifications")
    : null
  readonly property bool dnd: notificationService ? notificationService.doNotDisturb : false

  active: dnd
  activeText: "󰂛"
  inactiveText: "󰂛"
  activeTooltipText: "Allow Notifications"
  inactiveTooltipText: "Silence Notifications"

  onPressed: function() {
    if (root.notificationService) {
      root.notificationService.setDoNotDisturb(!root.notificationService.doNotDisturb)
    }
  }
}
