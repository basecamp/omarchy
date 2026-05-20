import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "clock"

  property bool alt: false

  function label() {
    if (alt) return Qt.formatDateTime(clock.date, String(setting("formatAlt", "dd MMMM 'W'ww yyyy")))
    if (bar && bar.vertical) return Qt.formatDateTime(clock.date, String(setting("verticalFormat", "HH\n—\nmm")))
    return Qt.formatDateTime(clock.date, String(setting("format", "dddd HH:mm")))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label()
    horizontalMargin: 8.75
    verticalPadding: 8.75
    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton) root.bar.run("omarchy-launch-floating-terminal-with-presentation omarchy-tz-select")
      else root.alt = !root.alt
    }
  }
}
