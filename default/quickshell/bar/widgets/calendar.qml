import QtQuick
import QtQuick.Layouts
import Quickshell
import "../common" as Common

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "calendar"
  property var settings: ({})

  property date now: new Date()
  property date viewMonth: new Date()
  property bool popupOpen: false

  function closePopout() { popupOpen = false }

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

  function shiftMonth(delta) {
    var date = new Date(viewMonth)
    date.setDate(1)
    date.setMonth(date.getMonth() + delta)
    viewMonth = date
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  SystemClock {
    id: clockTimer
    precision: SystemClock.Minutes
    onDateChanged: root.now = clockTimer.date
  }

  Common.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.formatLabel()
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: Qt.formatDateTime(root.now, "dddd, MMMM d, yyyy")

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.bar.run("omarchy-launch-floating-terminal-with-presentation omarchy-tz-select")
      } else {
        root.viewMonth = new Date(root.now)
        root.popupOpen = !root.popupOpen
      }
    }
  }

  Common.PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    open: root.popupOpen
    contentWidth: 300
    contentHeight: header.implicitHeight + grid.implicitHeight + 36

    Column {
      anchors.fill: parent
      spacing: 8

      Item {
        id: header
        width: parent.width
        implicitHeight: 28

        Common.PillButton {
          id: prevButton
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          iconText: ""
          foreground: root.bar.foreground
          horizontalPadding: 8
          verticalPadding: 4
          onClicked: root.shiftMonth(-1)
        }

        Text {
          anchors.centerIn: parent
          text: Qt.formatDate(root.viewMonth, "MMMM yyyy")
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 14
          font.bold: true
        }

        Common.PillButton {
          id: nextButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: ""
          foreground: root.bar.foreground
          horizontalPadding: 8
          verticalPadding: 4
          onClicked: root.shiftMonth(1)
        }
      }

      Grid {
        id: grid
        columns: 7
        rowSpacing: 4
        columnSpacing: 4
        width: parent.width

        Repeater {
          model: ["S", "M", "T", "W", "T", "F", "S"]

          Item {
            required property string modelData
            width: (grid.width - grid.columnSpacing * 6) / 7
            height: 18

            Text {
              anchors.centerIn: parent
              text: modelData
              color: Qt.darker(root.bar.foreground, 1.6)
              font.family: root.bar.fontFamily
              font.pixelSize: 11
              font.bold: true
            }
          }
        }

        Repeater {
          model: 42

          Rectangle {
            required property int index

            readonly property var startOfMonth: {
              var d = new Date(root.viewMonth)
              d.setDate(1)
              return d
            }
            readonly property int firstDayOffset: startOfMonth.getDay()
            readonly property var dayDate: {
              var d = new Date(startOfMonth)
              d.setDate(d.getDate() + index - firstDayOffset)
              return d
            }
            readonly property bool inMonth: dayDate.getMonth() === root.viewMonth.getMonth()
            readonly property bool isToday: {
              var n = root.now
              return dayDate.getDate() === n.getDate() && dayDate.getMonth() === n.getMonth() && dayDate.getFullYear() === n.getFullYear()
            }

            width: (grid.width - grid.columnSpacing * 6) / 7
            height: 28
            radius: 4
            color: isToday ? root.bar.foreground : "transparent"
            border.color: isToday ? root.bar.foreground : "transparent"
            border.width: isToday ? 1 : 0

            Text {
              anchors.centerIn: parent
              text: dayDate.getDate()
              color: isToday ? root.bar.background : (inMonth ? root.bar.foreground : Qt.darker(root.bar.foreground, 2.2))
              font.family: root.bar.fontFamily
              font.pixelSize: 12
              font.bold: isToday
            }
          }
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    visible: false
    enabled: false
  }
}
