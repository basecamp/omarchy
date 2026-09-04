import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.menu"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\ue900"
    fontFamily: "omarchy"
    horizontalMargin: 7.5
    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton)
        root.bar.run("xdg-terminal-exec")
      else if (root.bar.shell && typeof root.bar.shell.toggle === "function")
        root.bar.shell.toggle("omarchy.menu", JSON.stringify({ menu: "root" }))
      else
        root.bar.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'")
    }
  }
}
