import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy.clock"
  ipcTarget: "omarchy.clock"
  manageIpc: false

  property var anchorItem: null
  property var host: null
  property date displayDate: clock.date
  property date calendarDate: clock.date

  readonly property string dateFormat: setting("formatAlt", "dd MMMM 'W'ww yyyy")
  readonly property bool mondayFirstDayOfWeek: setting("mondayFirstDayOfWeek", false) === true
  readonly property int calendarColumns: 7
  readonly property int calendarRows: 6
  readonly property var monthStart: new Date(calendarDate.getFullYear(), calendarDate.getMonth(), 1)
  readonly property int firstWeekday: mondayFirstDayOfWeek ? 1 : localeFirstWeekday()
  readonly property var weekdayLabels: buildWeekdayLabels()
  readonly property var calendarCells: buildCalendarCells()
  readonly property color popupForeground: Color.popups.text
  readonly property color popupDim: Qt.darker(popupForeground, 1.45)
  readonly property color popupMuted: Qt.darker(popupForeground, 1.8)
  readonly property string popupFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string moonPhaseMarker: moonPhaseGlyph(displayDate)

  function refresh() {
    displayDate = new Date()
    if (host && host.refresh) host.refresh()
  }

  function open() {
    refresh()
    resetCalendarDate()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function resetCalendarDate() {
    calendarDate = new Date(displayDate.getFullYear(), displayDate.getMonth(), displayDate.getDate())
  }

  function daysInMonth(year, month) {
    return new Date(year, month + 1, 0).getDate()
  }

  function moveCalendar(monthDelta, yearDelta) {
    var year = calendarDate.getFullYear() + yearDelta
    var month = calendarDate.getMonth() + monthDelta
    var day = Math.min(calendarDate.getDate(), daysInMonth(year, month))
    calendarDate = new Date(year, month, day)
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

    for (var i = 0; i < calendarRows * calendarColumns; ++i) {
      var day = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i)
      cells.push({
        day: day.getDate(),
        inMonth: day.getMonth() === monthStart.getMonth(),
        today: dateKey(day) === today
      })
    }

    return cells
  }

  function moonPhaseIndex(date, phaseCount) {
    var synodicMonth = 29.530588853
    var knownNewMoon = Date.UTC(2000, 0, 6, 18, 14)
    var noonUtc = Date.UTC(date.getFullYear(), date.getMonth(), date.getDate(), 12)
    var days = (noonUtc - knownNewMoon) / 86400000
    var phase = days / synodicMonth
    phase = phase - Math.floor(phase)
    return Math.floor(phase * phaseCount + 0.5) % phaseCount
  }

  function moonPhaseGlyph(date) {
    var glyphs = [
      "\uE38D", // nf-weather-moon_new
      "\uE38E", // nf-weather-moon_waxing_crescent_1
      "\uE38F", // nf-weather-moon_waxing_crescent_2
      "\uE390", // nf-weather-moon_waxing_crescent_3
      "\uE391", // nf-weather-moon_waxing_crescent_4
      "\uE392", // nf-weather-moon_waxing_crescent_5
      "\uE393", // nf-weather-moon_waxing_crescent_6
      "\uE394", // nf-weather-moon_first_quarter
      "\uE395", // nf-weather-moon_waxing_gibbous_1
      "\uE396", // nf-weather-moon_waxing_gibbous_2
      "\uE397", // nf-weather-moon_waxing_gibbous_3
      "\uE398", // nf-weather-moon_waxing_gibbous_4
      "\uE399", // nf-weather-moon_waxing_gibbous_5
      "\uE39A", // nf-weather-moon_waxing_gibbous_6
      "\uE39B", // nf-weather-moon_full
      "\uE39C", // nf-weather-moon_waning_gibbous_1
      "\uE39D", // nf-weather-moon_waning_gibbous_2
      "\uE39E", // nf-weather-moon_waning_gibbous_3
      "\uE39F", // nf-weather-moon_waning_gibbous_4
      "\uE3A0", // nf-weather-moon_waning_gibbous_5
      "\uE3A1", // nf-weather-moon_waning_gibbous_6
      "\uE3A2", // nf-weather-moon_third_quarter
      "\uE3A3", // nf-weather-moon_waning_crescent_1
      "\uE3A4", // nf-weather-moon_waning_crescent_2
      "\uE3A5", // nf-weather-moon_waning_crescent_3
      "\uE3A6", // nf-weather-moon_waning_crescent_4
      "\uE3A7", // nf-weather-moon_waning_crescent_5
      "\uE3A8"  // nf-weather-moon_waning_crescent_6
    ]
    return glyphs[moonPhaseIndex(date, glyphs.length)]
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.displayDate = date
  }

  IpcHandler {
    target: "omarchy.clock"
    function refresh() { root.refresh() }
    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
  }

  KeyboardPanel {
    id: calendarPanel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: calendarPanel.fittedContentWidth(Style.space(300))
    contentHeight: calendarPanel.fittedContentHeight(calendarColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveCalendar(dx, 0)
        else if (dy !== 0) root.moveCalendar(0, dy)
      }
      onActivateRequested: root.resetCalendarDate()
      onCloseRequested: root.close()

      Column {
        id: calendarColumn
        anchors.fill: parent
        spacing: Style.space(12)

        Item {
          width: parent.width
          implicitHeight: Math.max(dateHeading.implicitHeight, moonPhase.implicitHeight)

          Text {
            id: dateHeading
            anchors.centerIn: parent
            width: Math.max(1, parent.width - (moonPhase.implicitWidth + Style.space(8)) * 2)
            text: root.formatted(root.calendarDate, root.dateFormat)
            color: root.popupForeground
            font.family: root.popupFontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }

          Text {
            id: moonPhase
            anchors.top: parent.top
            anchors.right: parent.right
            text: root.moonPhaseMarker
            color: root.popupMuted
            opacity: 0.82
            font.family: root.popupFontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignTop
          }
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
          columns: root.calendarColumns
          rowSpacing: 0
          columnSpacing: Style.space(4)

          readonly property int cellSize: Math.floor((width - columnSpacing * (root.calendarColumns - 1)) / root.calendarColumns)

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
          columns: root.calendarColumns
          rowSpacing: Style.space(4)
          columnSpacing: Style.space(4)

          readonly property int cellSize: Math.floor((width - columnSpacing * (root.calendarColumns - 1)) / root.calendarColumns)

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
}
