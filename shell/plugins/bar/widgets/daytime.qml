import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "daytime"

  property date now: new Date()

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function formatLabel() {
    if (!bar) return ""
    var fmt = bar.vertical
      ? String(setting("verticalFormat", "HH\n—\nmm"))
      : String(setting("format", "dddd HH:mm"))
    return Qt.formatDateTime(now, fmt)
  }

  function tooltipLabel() {
    return Qt.formatDateTime(root.now, String(setting("formatAlt", "dd MMMM yyyy")))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  SystemClock {
    id: clockTimer
    precision: SystemClock.Minutes
    onDateChanged: root.now = clockTimer.date
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.formatLabel()
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.tooltipLabel()
    pressable: false
  }
}
