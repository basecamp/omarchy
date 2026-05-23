import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.clock"

  property bool calendarOpen: false
  property date displayDate: clock.date

  readonly property string timeFormat: bar && bar.vertical
    ? setting("verticalFormat", "HH\n—\nmm")
    : setting("format", "dddd HH:mm")
  readonly property string dateFormat: setting("formatAlt", "dd MMMM 'W'ww yyyy")
  readonly property var monthStart: new Date(displayDate.getFullYear(), displayDate.getMonth(), 1)
  readonly property int firstWeekday: localeFirstWeekday()
  readonly property var weekdayLabels: buildWeekdayLabels()
  readonly property var calendarCells: buildCalendarCells()
  readonly property color popupForeground: Color.popups.text
  readonly property color popupDim: Qt.darker(popupForeground, 1.45)
  readonly property color popupMuted: Qt.darker(popupForeground, 1.8)
  readonly property string popupFontFamily: bar ? bar.fontFamily : Style.font.family

  function refresh() {
    displayDate = new Date()
  }

  function openCalendar() {
    refresh()
    calendarOpen = true
  }

  function close() {
    calendarOpen = false
  }

  function closeForPopoutSwitch() {
    close()
  }

  function toggleCalendar() {
    if (calendarOpen) close()
    else openCalendar()
  }

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

  function formatted(date, format) {
    var fmt = String(format || "")
    return Qt.formatDateTime(date, fmt.replace(/ww/g, isoWeekLiteral(date)))
  }

  function localeFirstWeekday() {
    var day = Qt.locale().firstDayOfWeek
    if (day === undefined || day === null) return 0
    var n = Number(day)
    if (!isFinite(n)) return 0
    return ((Math.round(n) % 7) + 7) % 7
  }

  function pad2(n) {
    return n < 10 ? "0" + n : "" + n
  }

  function dateKey(date) {
    return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate())
  }

  function buildWeekdayLabels() {
    var labels = []
    var sunday = new Date(2023, 0, 1)
    for (var i = 0; i < 7; ++i) {
      var dayIndex = (firstWeekday + i) % 7
      var day = new Date(sunday.getFullYear(), sunday.getMonth(), sunday.getDate() + dayIndex)
      labels.push(Qt.formatDate(day, "ddd").toUpperCase())
    }
    return labels
  }

  function buildCalendarCells() {
    var cells = []
    var offset = (monthStart.getDay() - firstWeekday + 7) % 7
    var start = new Date(monthStart.getFullYear(), monthStart.getMonth(), 1 - offset)
    var today = dateKey(displayDate)

    for (var i = 0; i < 42; ++i) {
      var day = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i)
      cells.push({
        day: day.getDate(),
        inMonth: day.getMonth() === monthStart.getMonth(),
        today: dateKey(day) === today
      })
    }

    return cells
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.displayDate = date
  }

  IpcHandler {
    target: "omarchy.clock"
    function refresh(): void { root.refresh() }
    function open(): void { root.openCalendar() }
    function close(): void { root.close() }
    function toggle(): void { root.toggleCalendar() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.formatted(root.displayDate, root.timeFormat)
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: ""
    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton) root.bar.run("omarchy-menu-timezone")
      else root.toggleCalendar()
    }
  }

  PopupCard {
    id: calendarPopup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.calendarOpen
    triggerMode: "click"
    contentWidth: calendarPopup.fittedContentWidth(Style.space(300))
    contentHeight: calendarPopup.fittedContentHeight(calendarColumn.implicitHeight)

    Column {
      id: calendarColumn
      anchors.fill: parent
      spacing: Style.space(12)

      Text {
        width: parent.width
        text: root.formatted(root.displayDate, root.dateFormat)
        color: root.popupForeground
        font.family: root.popupFontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }

      Rectangle {
        width: parent.width
        height: Style.spacing.hairline
        color: root.popupForeground
        opacity: 0.12
      }

      Grid {
        id: weekdayGrid
        width: parent.width
        columns: 7
        rowSpacing: 0
        columnSpacing: Style.space(4)

        readonly property int cellSize: Math.floor((width - columnSpacing * 6) / 7)

        Repeater {
          model: root.weekdayLabels

          Text {
            required property var modelData
            width: weekdayGrid.cellSize
            height: Style.space(16)
            text: modelData
            color: root.popupDim
            font.family: root.popupFontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }
        }
      }

      Grid {
        id: calendarGrid
        width: parent.width
        columns: 7
        rowSpacing: Style.space(4)
        columnSpacing: Style.space(4)

        readonly property int cellSize: Math.floor((width - columnSpacing * 6) / 7)

        Repeater {
          model: root.calendarCells

          Item {
            required property var modelData

            width: calendarGrid.cellSize
            height: Style.space(28)

            Rectangle {
              anchors.fill: parent
              radius: Math.min(Style.cornerRadius, Style.space(6))
              color: modelData.today ? Style.selectedFillFor(root.popupForeground, Color.accent) : "transparent"
              border.color: modelData.today ? Style.selectedBorderFor(root.popupForeground, Color.accent) : "transparent"
              border.width: modelData.today ? Style.selectedBorderWidth : 0
            }

            Text {
              anchors.centerIn: parent
              text: String(modelData.day)
              color: modelData.inMonth ? root.popupForeground : root.popupMuted
              opacity: modelData.inMonth ? 1.0 : 0.45
              font.family: root.popupFontFamily
              font.pixelSize: Style.font.body
              font.bold: modelData.today
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
            }
          }
        }
      }
    }
  }
}
