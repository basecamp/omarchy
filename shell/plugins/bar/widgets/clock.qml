import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "clock"

  property bool alt: false

  // Qt.formatDateTime doesn't recognize `ww` (ISO week number). Pre-substitute
  // it as a Qt-quoted literal before formatting so users can write the natural
  // `'W'ww yyyy` and get `W21 2026` rather than `Www 2026`.
  function isoWeek(date) {
    var d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()))
    var day = d.getUTCDay() || 7
    d.setUTCDate(d.getUTCDate() + 4 - day)
    var yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1))
    return Math.ceil(((d - yearStart) / 86400000 + 1) / 7)
  }

  function format(date, fmt) {
    var f = String(fmt || "")
    if (f.indexOf("ww") !== -1) {
      var w = isoWeek(date)
      var ww = w < 10 ? "0" + w : String(w)
      f = f.replace(/ww/g, "'" + ww + "'")
    }
    return Qt.formatDateTime(date, f)
  }

  function label() {
    if (alt) return format(clock.date, setting("formatAlt", "dd MMMM 'W'ww yyyy"))
    if (bar && bar.vertical) return format(clock.date, setting("verticalFormat", "HH\n—\nmm"))
    return format(clock.date, setting("format", "dddd HH:mm"))
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
