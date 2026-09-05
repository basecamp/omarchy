import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "PlannerModel.js" as PlannerModel

// The original month calendar, extracted from Panel.qml. Its public signals
// keep date navigation, week-start preferences, and the memento-mori editor in
// the coordinator, while this file owns all calendar geometry and painting.
Item {
  id: root

  property var service: null
  property var bar: null
  property date today: new Date()
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()
  property int weekStart: 1
  property bool editingLife: false
  property int birthYear: 0
  property int lifeExpectancy: 0
  property color foreground: bar ? bar.foreground : Color.foreground
  property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()
  readonly property string todayKey: Model.keyForDate(today)
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)
  readonly property var markerMap: PlannerModel.eventMarkers(
    root.service && root.service.calendarState ? root.service.calendarState.events : [],
    root.service && root.service.calendarState ? root.service.calendarState.settings.timezone : "")

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)
  readonly property var labelLocale: Qt.locale("en_US")
  readonly property string nextWeekStartLabel: labelLocale.dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)

  signal todayRequested()
  signal monthRequested(int delta)
  signal weekStartRequested()
  signal plannerRequested()
  signal lifeEditRequested()
  signal lifeClearRequested()
  signal lifeCommitRequested(string birth, string expectancy)
  signal lifeCancelRequested()

  implicitHeight: calendarColumn.implicitHeight

  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  function markerCount(key) {
    return Number(root.markerMap[key] || 0)
  }

  function beginLifeEdit() {
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.lifeCancelRequested()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.lifeCommitRequested(bornField.text, expectancyField.text)
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  onEditingLifeChanged: if (root.editingLife) root.beginLifeEdit()

  Flickable {
    id: calendarScroll
    anchors.fill: parent
    contentWidth: calendarColumn.width
    contentHeight: calendarColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height || contentWidth > width

    Column {
      id: calendarColumn
      width: Math.max(calendarScroll.width, gridColumn.width)
      spacing: Style.space(8)

      Item {
        width: parent.width
        height: heroRow.height

        Row {
          id: heroRow
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(22)

          Text {
            textFormat: Text.PlainText
            anchors.baseline: heroDate.baseline
            text: "󰃭"
            color: heroMouse.containsMouse
              ? Style.hoverStateColor(root.foreground, Color.accent)
              : root.foreground
            font.family: root.fontFamily
            font.pixelSize: 48
          }

          Text {
            textFormat: Text.PlainText
            id: heroDate
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDate(root.today, "MMMM d")
            color: heroMouse.containsMouse
              ? Style.hoverStateColor(root.foreground, Color.accent)
              : root.foreground
            font.family: root.fontFamily
            font.pixelSize: 52
            font.bold: true
          }
        }

        MouseArea {
          id: heroMouse
          x: heroRow.x
          y: heroRow.y
          width: heroRow.width
          height: heroRow.height
          enabled: !root.viewingCurrentMonth
          hoverEnabled: enabled
          cursorShape: Qt.PointingHandCursor
          onClicked: root.todayRequested()

          PanelToolTip {
            visible: heroMouse.containsMouse
            text: "Back to today"
            fontFamily: root.fontFamily
          }
        }
      }

      Item {
        width: parent.width
        height: yearBlock.y + yearBlock.height

        Item {
          id: yearBlock
          y: Style.space(6)
          anchors.horizontalCenter: parent.horizontalCenter
          width: gridColumn.width
          height: Math.max(yearLabel.implicitHeight, Style.space(10))

          TapHandler {
            enabled: !root.editingLife
            onDoubleTapped: root.lifeEditRequested()
          }

          Row {
            visible: root.editingLife
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(10)

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: "BORN"
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: 1
            }

            TextField {
              id: bornField
              width: Style.space(70)
              anchors.verticalCenter: parent.verticalCenter
              placeholderText: "year"
              foreground: root.foreground
              font.family: root.fontFamily
              inputMethodHints: Qt.ImhDigitsOnly
              Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
            }

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              leftPadding: Style.space(6)
              text: "LIVE TO"
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: 1
            }

            TextField {
              id: expectancyField
              width: Style.space(60)
              anchors.verticalCenter: parent.verticalCenter
              placeholderText: "90"
              foreground: root.foreground
              font.family: root.fontFamily
              inputMethodHints: Qt.ImhDigitsOnly
              Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
            }
          }

          Text {
            textFormat: Text.PlainText
            id: yearLabel
            visible: !root.editingLife
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.today.getFullYear()
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
          }

          Text {
            textFormat: Text.PlainText
            id: yearPercent
            visible: !root.editingLife
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.yearDonePercent + "%"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Rectangle {
            id: yearTrack
            visible: !root.editingLife
            anchors.left: yearLabel.right
            anchors.right: yearPercent.left
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(6)
            radius: Style.cornerRadius > 0 ? height / 2 : 0
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

            Rectangle {
              width: Math.round(parent.width * root.yearDone)
              height: parent.height
              radius: parent.radius
              color: Style.selectedStateColor(root.foreground, Color.accent)
              Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }
          }
        }
      }

      Item {
        visible: root.birthYear > 0
        width: parent.width
        height: visible ? lifeBlock.height : 0

        Item {
          id: lifeBlock
          anchors.horizontalCenter: parent.horizontalCenter
          width: gridColumn.width
          height: Math.max(lifeLabel.implicitHeight, Style.space(10))

          Text {
            textFormat: Text.PlainText
            id: lifeLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "LIFE"
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
          }

          Text {
            textFormat: Text.PlainText
            id: lifePercent
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.lifeDonePercent + "%"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Rectangle {
            anchors.left: lifeLabel.right
            anchors.right: lifePercent.left
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(6)
            radius: Style.cornerRadius > 0 ? height / 2 : 0
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

            Rectangle {
              width: Math.round(parent.width * root.lifeDone)
              height: parent.height
              radius: parent.radius
              color: Style.selectedStateColor(root.foreground, Color.accent)
              Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }
          }

          TapHandler { onDoubleTapped: root.lifeClearRequested() }

          MouseArea {
            id: lifeMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            PanelToolTip {
              visible: lifeMouse.containsMouse
              text: "Memento Mori"
              fontFamily: root.fontFamily
            }
          }
        }
      }

      Item {
        width: parent.width
        height: gridColumn.y + gridColumn.height

        WheelHandler {
          onWheel: function(event) {
            if (event.angleDelta.y === 0) return
            root.monthRequested(event.angleDelta.y > 0 ? -1 : 1)
          }
        }

        Column {
          id: gridColumn
          y: Style.space(18)
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(3)

          Row {
            id: headerRow
            spacing: root.cellSpacing

            Rectangle {
              width: root.weekColumnWidth
              height: Style.space(16)
              radius: Style.cornerRadius
              color: weekStartMouse.containsMouse
                ? Style.hoverFillFor(root.foreground, Color.accent)
                : "transparent"

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "W"
                color: weekStartMouse.containsMouse
                  ? Style.hoverStateColor(root.foreground, Color.accent)
                  : Qt.darker(root.foreground, 1.9)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
                font.bold: true
              }

              MouseArea {
                id: weekStartMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.weekStartRequested()
              }

              PanelToolTip {
                visible: weekStartMouse.containsMouse
                text: "Start weeks on " + root.nextWeekStartLabel
                fontFamily: root.fontFamily
              }
            }

            Item { width: root.gutterWidth; height: Style.space(16) }

            Repeater {
              model: root.weekdays
              Text {
                textFormat: Text.PlainText
                required property var modelData
                width: root.cellWidth
                height: Style.space(16)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.weekdayLabel(modelData)
                color: Qt.darker(root.foreground, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
                font.bold: true
              }
            }
          }

          Repeater {
            model: root.weeks
            Row {
              required property var modelData
              spacing: root.cellSpacing

              Text {
                textFormat: Text.PlainText
                width: root.weekColumnWidth
                height: root.cellHeight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: modelData.week
                color: Qt.darker(root.foreground, 1.9)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Item { width: root.gutterWidth; height: root.cellHeight }

              Repeater {
                model: modelData.days
                Rectangle {
                  required property var modelData
                  width: root.cellWidth
                  height: root.cellHeight
                  radius: Style.cornerRadius
                  color: "transparent"
                  border.width: modelData.today ? Style.spacing.hairline : 0
                  border.color: Style.normalBorderFor(root.foreground, Color.accent)

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: modelData.day
                    color: modelData.inMonth
                      ? (modelData.weekend ? Qt.darker(root.foreground, 1.45) : root.foreground)
                      : Qt.darker(root.foreground, 2.2)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: modelData.today
                  }

                  Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Style.space(3)
                    spacing: Style.space(2)
                    visible: root.markerCount(modelData.key) > 0
                    Repeater {
                      model: Math.min(root.markerCount(modelData.key), 3)
                      Rectangle {
                        required property int index
                        width: Style.space(3)
                        height: width
                        radius: width / 2
                        color: Color.accent
                      }
                    }
                  }
                }
              }
            }
          }
        }

        Rectangle {
          x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
          y: gridColumn.y + headerRow.height + gridColumn.spacing
          width: Style.spacing.hairline
          height: gridColumn.height - headerRow.height - gridColumn.spacing
          color: root.foreground
          opacity: 0.1
        }
      }

      Item {
        width: parent.width
        height: monthNav.height

        Item {
          id: monthNav
          anchors.horizontalCenter: parent.horizontalCenter
          width: gridColumn.width
          height: monthLabel.implicitHeight + Style.space(10)

          Text {
            textFormat: Text.PlainText
            id: monthLabel
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(130)
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.letterSpacing: 1
          }

          PanelActionButton {
            anchors.left: parent.left
            anchors.leftMargin: -Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰅁"
            tooltipText: "Previous month"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.monthRequested(-1)
          }

          PanelActionButton {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(30)
            anchors.verticalCenter: parent.verticalCenter
            iconText: "P"
            tooltipText: "Open planner"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: root.plannerRequested()
          }

          PanelActionButton {
            anchors.right: parent.right
            anchors.rightMargin: -Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰅂"
            tooltipText: "Next month"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.monthRequested(1)
          }
        }
      }
    }
  }
}
