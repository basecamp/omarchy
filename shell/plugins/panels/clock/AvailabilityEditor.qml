import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Weekly availability editor. Each day gets an always-available add row and
// can grow without changing the normalized state shape: weekday -> [{start,end}].
Item {
  id: root

  property var service: null
  property var bar: null
  property color foreground: bar ? bar.foreground : Color.foreground
  property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property var days: ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
  property var draft: ({})
  property string errorText: ""

  signal saved()
  signal cancelled()

  // The popup grows with the form when space allows. On shorter screens only
  // the weekday list scrolls; the action row stays pinned in view.
  implicitHeight: form.implicitHeight + footer.implicitHeight + Style.space(44)

  function copy(value) { return JSON.parse(JSON.stringify(value || {})) }

  function loadDraft() {
    var source = root.service && root.service.calendarState
      ? root.service.calendarState.settings.availability
      : {}
    var next = {}
    for (var i = 0; i < root.days.length; i++)
      next[root.days[i]] = Array.isArray(source[root.days[i]]) ? copy(source[root.days[i]]) : []
    root.draft = next
    root.errorText = ""
  }

  function windowValue(day, slot) {
    var list = root.draft[day]
    if (!Array.isArray(list) || !list[slot]) return { start: "", end: "" }
    return { start: String(list[slot].start || ""), end: String(list[slot].end || "") }
  }

  function rowCount(day) {
    var list = root.draft[day]
    return Math.max(1, (Array.isArray(list) ? list.length : 0) + 1)
  }

  function setWindow(day, slot, start, end) {
    var next = copy(root.draft)
    if (!Array.isArray(next[day])) next[day] = []
    while (next[day].length <= slot) next[day].push({ start: "", end: "" })
    next[day][slot] = { start: String(start || "").trim(), end: String(end || "").trim() }
    root.draft = next
  }

  function removeWindow(day, slot) {
    var next = copy(root.draft)
    if (Array.isArray(next[day])) next[day].splice(slot, 1)
    root.draft = next
  }

  function clock(value) {
    var match = String(value || "").trim().match(/^(\d{1,2}):(\d{1,2})$/)
    if (!match) return false
    var hours = Number(match[1])
    var minutes = Number(match[2])
    if (hours >= 24 || minutes >= 60) return false
    return (hours < 10 ? "0" : "") + hours + ":" + (minutes < 10 ? "0" : "") + minutes
  }

  function save() {
    var result = {}
    var count = 0
    for (var i = 0; i < root.days.length; i++) {
      var day = root.days[i]
      var source = Array.isArray(root.draft[day]) ? root.draft[day] : []
      var windows = []
      for (var slot = 0; slot < source.length; slot++) {
        var value = source[slot] || {}
        var start = String(value.start || "").trim()
        var end = String(value.end || "").trim()
        if (start === "" && end === "") continue
        var normalizedStart = clock(start)
        var normalizedEnd = clock(end)
        if (!normalizedStart || !normalizedEnd || normalizedEnd <= normalizedStart) {
          root.errorText = "Each availability window needs a start before its end (HH:MM)."
          return
        }
        windows.push({ start: normalizedStart, end: normalizedEnd })
        count += 1
      }
      if (windows.length > 0) result[day] = windows
    }
    if (count === 0) {
      root.errorText = "Add at least one weekly availability window before saving."
      return
    }
    var next = root.service ? root.service.updateSettings({ availability: result }) : null
    if (next) root.saved()
    else root.errorText = root.service ? root.service.lastSolverError : "Availability could not be saved."
  }

  Component.onCompleted: loadDraft()
  onServiceChanged: loadDraft()

  Rectangle {
    anchors.fill: parent
    color: Color.popups.background
    border.width: Style.spacing.hairline
    border.color: Color.popups.border
    radius: Style.cornerRadius
  }

  Item {
    id: viewport
    anchors.fill: parent
    anchors.margins: Style.space(18)
    clip: true

    ScrollView {
      id: bodyScroll
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: footer.top
      anchors.bottomMargin: Style.space(10)
      contentWidth: form.width
      contentHeight: form.implicitHeight
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      ScrollBar.vertical.policy: form.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

      Column {
      id: form
        width: Math.max(bodyScroll.width, Style.space(390))
        spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: "Weekly availability"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        text: "Omarchy may schedule tasks only inside these local-time windows."
        color: Qt.darker(root.foreground, 1.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        width: parent.width
      }

      Repeater {
        model: root.days
        delegate: Column {
          required property string modelData
          property string day: modelData
          width: form.width
          spacing: Style.space(3)

          Text {
            textFormat: Text.PlainText
            text: day.charAt(0).toUpperCase() + day.slice(1)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Repeater {
            model: root.rowCount(day)
            delegate: Row {
              required property int index
              width: parent.width
              spacing: Style.space(6)

              Text {
                textFormat: Text.PlainText
                width: Style.space(42)
                anchors.verticalCenter: parent.verticalCenter
                text: "Slot " + (index + 1)
                color: Qt.darker(root.foreground, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              TextField {
                id: startField
                width: Style.space(100)
                foreground: root.foreground
                font.family: root.fontFamily
                placeholderText: "09:00"
                text: root.windowValue(day, index).start
                onEditingFinished: root.setWindow(day, index, text, endField.text)
                Keys.onEscapePressed: root.cancelled()
                Component.onCompleted: if (day === "monday" && index === 0) forceActiveFocus()
              }
              Text {
                textFormat: Text.PlainText
                text: "—"
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.darker(root.foreground, 1.5)
              }
              TextField {
                id: endField
                width: Style.space(100)
                foreground: root.foreground
                font.family: root.fontFamily
                placeholderText: "17:00"
                text: root.windowValue(day, index).end
                onEditingFinished: root.setWindow(day, index, startField.text, text)
                Keys.onReturnPressed: {
                  if (day === "monday" && index === 0) {
                    root.setWindow(day, index, startField.text, text)
                    Qt.callLater(root.save)
                  }
                }
                Keys.onEscapePressed: root.cancelled()
              }
              Button {
                focusable: true
                anchors.verticalCenter: parent.verticalCenter
                foreground: root.foreground
                bordered: true
                fontFamily: root.fontFamily
                text: root.windowValue(day, index).start !== "" ? "Remove" : "Add"
                onClicked: {
                  var value = root.windowValue(day, index)
                  if (value.start !== "") root.removeWindow(day, index)
                  else root.setWindow(day, index, "09:00", "17:00")
                }
              }
            }
          }
        }
      }

        Text {
          textFormat: Text.PlainText
          text: root.errorText
          visible: root.errorText !== ""
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          width: parent.width
        }
      }
    }

    Row {
      id: footer
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      spacing: Style.space(8)
      Button {
        focusable: true
        text: "Save availability"
        foreground: activeFocus || hot ? Color.foreground : Color.background
        background: Color.accent
        fontFamily: root.fontFamily
        onClicked: root.save()
      }
      Button {
        focusable: true
        text: "Cancel"
        foreground: root.foreground
        bordered: true
        fontFamily: root.fontFamily
        onClicked: root.cancelled()
      }
    }
  }
}
