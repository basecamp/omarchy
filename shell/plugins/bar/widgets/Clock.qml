import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "Clock"

  property bool alt: false

  readonly property string activeFormat: alt
    ? setting("formatAlt", "dd MMMM 'W'ww yyyy")
    : (bar && bar.vertical ? setting("verticalFormat", "HH\n—\nmm") : setting("format", "dddd HH:mm"))

  function isoWeek(date) {
    var d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()))
    var day = d.getUTCDay() || 7
    d.setUTCDate(d.getUTCDate() + 4 - day)
    var yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1))
    return Math.ceil(((d - yearStart) / 86400000 + 1) / 7)
  }

  function isoWeekLiteral(date) {
    var week = isoWeek(date)
    return (week < 10 ? "0" : "") + week
  }

  function formatted(date) {
    return Qt.formatDateTime(date, activeFormat.replace(/ww/g, isoWeekLiteral(date)))
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
    text: root.formatted(clock.date)
    horizontalMargin: 8.75
    verticalPadding: 8.75
    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton) root.bar.run("omarchy-launch-floating-terminal-with-presentation omarchy-tz-select")
      else root.alt = !root.alt
    }
  }
}
