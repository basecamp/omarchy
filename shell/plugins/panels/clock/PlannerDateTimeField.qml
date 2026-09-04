import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as ClockModel

// Human-friendly date/time input for planner forms. The state layer still
// stores ISO timestamps, but users choose a day from a calendar and only
// enter the small, familiar HH:MM time value.
Item {
  id: root

  property string label: ""
  property string value: ""
  property bool allowEmpty: false
  property string emptyLabel: "Choose a date"
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property string errorText: ""

  readonly property bool valid: root.allowEmpty && root.value === ""
    ? true
    : root.validTime(timeField.text) && root.validValue(root.value)

  signal changed(string value)
  signal submitted()

  property date selectedDate: new Date()
  property int viewYear: selectedDate.getFullYear()
  property int viewMonth: selectedDate.getMonth()

  signal cancelled()

  function pad2(value) {
    return (Number(value) < 10 ? "0" : "") + Number(value)
  }

  function validValue(value) {
    if (value === "") return root.allowEmpty
    var parsed = new Date(value)
    return !isNaN(parsed.getTime())
  }

  function validTime(value) {
    var match = /^(\d{1,2}):([0-5]\d)$/.exec(String(value || "").trim())
    return !!match && Number(match[1]) >= 0 && Number(match[1]) <= 23
  }

  function timeParts(value) {
    var match = /^(\d{1,2}):([0-5]\d)$/.exec(String(value || "").trim())
    if (!match || Number(match[1]) > 23) return null
    return { hour: Number(match[1]), minute: Number(match[2]) }
  }

  function sourceDate() {
    if (root.value !== "") {
      var parsed = new Date(root.value)
      if (!isNaN(parsed.getTime())) return parsed
    }
    return new Date()
  }

  function syncFromValue() {
    var source = root.sourceDate()
    root.selectedDate = new Date(source.getFullYear(), source.getMonth(), source.getDate())
    root.viewYear = root.selectedDate.getFullYear()
    root.viewMonth = root.selectedDate.getMonth()
    timeField.text = root.value === "" ? "09:00" : root.pad2(source.getHours()) + ":" + root.pad2(source.getMinutes())
    root.errorText = ""
  }

  function displayDate() {
    return root.value === "" ? root.emptyLabel : Qt.formatDate(root.selectedDate, "ddd, d MMM yyyy")
  }

  function selectedValue() {
    var time = root.timeParts(timeField.text)
    if (!time) {
      root.errorText = "Enter a time as HH:MM, for example 09:00."
      timeField.forceActiveFocus()
      return false
    }

    var localDate = new Date(root.selectedDate.getFullYear(), root.selectedDate.getMonth(), root.selectedDate.getDate(), time.hour, time.minute, 0, 0)
    return localDate.toISOString()
  }

  function commitSelection() {
    var next = root.selectedValue()
    if (next === false) return
    root.errorText = ""
    root.changed(next)
    picker.close()
  }

  function submit() {
    var next = root.selectedValue()
    if (next === false) return
    root.errorText = ""
    root.changed(next)
    root.submitted()
  }

  function chooseDay(day) {
    root.selectedDate = new Date(day.year, day.month, day.day)
    root.viewYear = day.year
    root.viewMonth = day.month
    root.commitSelection()
  }

  function stepMonth(delta) {
    var next = ClockModel.stepMonth(root.viewYear, root.viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function moveDay(delta) {
    var next = new Date(root.selectedDate)
    next.setDate(next.getDate() + Number(delta))
    root.selectedDate = new Date(next.getFullYear(), next.getMonth(), next.getDate())
    root.viewYear = root.selectedDate.getFullYear()
    root.viewMonth = root.selectedDate.getMonth()
    Qt.callLater(root.focusSelectedDay)
  }

  function focusSelectedDay() {
    var wanted = ClockModel.keyForDate(root.selectedDate)
    for (var rowIndex = 0; rowIndex < dateGrid.children.length; rowIndex++) {
      var row = dateGrid.children[rowIndex]
      if (!row || !row.children) continue
      for (var dayIndex = 0; dayIndex < row.children.length; dayIndex++) {
        var day = row.children[dayIndex]
        if (day && day.dayKey === wanted) {
          day.forceActiveFocus()
          return
        }
      }
    }
  }

  function chooseToday() {
    var today = new Date()
    root.selectedDate = new Date(today.getFullYear(), today.getMonth(), today.getDate())
    root.viewYear = root.selectedDate.getFullYear()
    root.viewMonth = root.selectedDate.getMonth()
    root.commitSelection()
  }

  function clearValue() {
    root.errorText = ""
    root.changed("")
    picker.close()
  }

  Component.onCompleted: root.syncFromValue()
  onValueChanged: root.syncFromValue()

  implicitHeight: form.implicitHeight

  Column {
    id: form
    width: parent.width
    spacing: Style.spacing.labelGap

    Text {
      visible: root.label !== ""
      textFormat: Text.PlainText
      text: root.label
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Row {
      width: parent.width
      spacing: Style.space(8)

      Button {
        id: dateButton
        focusable: true
        enabled: root.enabled
        width: parent.width - timeField.width - parent.spacing
        text: root.displayDate()
        leftAlign: true
        foreground: root.foreground
        bordered: true
        fontFamily: root.fontFamily
        onClicked: {
          root.syncFromValue()
          picker.open()
        }
        Keys.onEscapePressed: root.cancelled()
      }

      TextField {
        id: timeField
        width: Style.space(78)
        enabled: root.enabled
        foreground: root.foreground
        font.family: root.fontFamily
        placeholderText: "09:00"
        inputMethodHints: Qt.ImhTime
        onEditingFinished: {
          if (root.validTime(text)) {
            var next = root.selectedValue()
            if (next !== false) root.changed(next)
            root.errorText = ""
          } else {
            root.errorText = "Enter a time as HH:MM, for example 09:00."
          }
        }
        Keys.onReturnPressed: root.submit()
        Keys.onEscapePressed: root.cancelled()
      }
    }

    Text {
      visible: root.errorText !== ""
      textFormat: Text.PlainText
      text: root.errorText
      color: Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
      width: parent.width
    }
  }

  Popup {
    id: picker
    x: 0
    y: form.height + Style.space(4)
    width: Math.max(root.width, Style.space(300))
    height: pickerContent.implicitHeight + padding * 2
    padding: Style.space(10)
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    onOpened: Qt.callLater(root.focusSelectedDay)

    background: BorderSurface {
      color: Color.popups.background
      borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Style.normalBorderWidth)
      radius: Style.cornerRadius
    }

    contentItem: Column {
      id: pickerContent
      spacing: Style.space(7)

      Row {
        width: parent.width
        spacing: Style.space(5)

        Button {
          id: previousMonth
          width: Style.space(30)
          height: Style.space(28)
          focusable: true
          text: "‹"
          foreground: root.foreground
          bordered: true
          fontFamily: root.fontFamily
          onClicked: root.stepMonth(-1)
        }

        Text {
          width: parent.width - previousMonth.width - nextMonth.width - parent.spacing * 2
          height: previousMonth.height
          textFormat: Text.PlainText
          text: Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }

        Button {
          id: nextMonth
          width: Style.space(30)
          height: Style.space(28)
          focusable: true
          text: "›"
          foreground: root.foreground
          bordered: true
          fontFamily: root.fontFamily
          onClicked: root.stepMonth(1)
        }
      }

      Row {
        spacing: Style.space(2)
        Repeater {
          model: ["M", "T", "W", "T", "F", "S", "S"]
          Text {
            required property string modelData
            width: Style.space(36)
            height: Style.space(18)
            textFormat: Text.PlainText
            text: modelData
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }

      Column {
        id: dateGrid
        spacing: Style.space(2)
        Repeater {
          model: ClockModel.monthGrid(root.viewYear, root.viewMonth, 1, ClockModel.keyForDate(new Date()))
          Row {
            required property var modelData
            spacing: Style.space(2)

            Repeater {
              model: modelData.days
              Button {
                required property var modelData
                width: Style.space(36)
                height: Style.space(30)
                focusable: true
                property string dayKey: modelData.key
                text: String(modelData.day)
                enabled: root.enabled
                selected: modelData.key === ClockModel.keyForDate(root.selectedDate)
                bordered: modelData.today
                foreground: modelData.inMonth ? root.foreground : Qt.darker(root.foreground, 2.0)
                background: "transparent"
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Left) root.moveDay(-1)
                  else if (event.key === Qt.Key_Right) root.moveDay(1)
                  else if (event.key === Qt.Key_Up) root.moveDay(-7)
                  else if (event.key === Qt.Key_Down) root.moveDay(7)
                  else return
                  event.accepted = true
                }
                onClicked: root.chooseDay(modelData)
              }
            }
          }
        }
      }

      Row {
        spacing: Style.space(8)

        Button {
          id: todayButton
          focusable: true
          text: "Today"
          foreground: root.foreground
          bordered: true
          fontFamily: root.fontFamily
          onClicked: root.chooseToday()
        }

        Button {
          visible: root.allowEmpty
          focusable: true
          text: "Clear"
          foreground: root.foreground
          bordered: true
          fontFamily: root.fontFamily
          onClicked: root.clearValue()
        }
      }
    }
  }
}
