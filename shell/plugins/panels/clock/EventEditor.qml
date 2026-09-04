import QtQuick
import qs.Commons
import qs.Ui

// Manual event editor. Event timestamps are entered as ISO-8601 values so the
// timezone and DST policy stay explicit all the way to the local planner.
Item {
  id: root

  property var service: null
  property var bar: null
  property var event: null
  property color foreground: bar ? bar.foreground : Color.foreground
  property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property string errorText: ""
  property bool allDay: false
  readonly property bool manualEvent: !root.event || root.event.origin === "manual"

  signal saved()
  signal cancelled()

  function defaultTimezone() {
    if (root.service && root.service.calendarState.settings.timezone)
      return root.service.calendarState.settings.timezone
    try { return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC" }
    catch (error) { return "UTC" }
  }

  function reset() {
    var value = root.event || {}
    titleField.text = value.title || ""
    startField.text = value.startAt || ""
    endField.text = value.endAt || ""
    timezoneField.text = value.timezone || defaultTimezone()
    descriptionField.text = value.description || ""
    recurrenceField.text = value.rrule || ""
    allDay = !!value.allDay
    errorText = ""
  }

  function requiredIso(field) {
    var value = String(field.text || "").trim()
    if (value === "") return false
    var parsed = new Date(value)
    return isNaN(parsed.getTime()) ? false : parsed.toISOString()
  }

  function save() {
    if (!root.manualEvent) {
      errorText = "Applied planner events are changed through the planner. Return the task to the inbox first."
      return
    }
    var title = titleField.text.trim()
    var startAt = requiredIso(startField)
    var endAt = requiredIso(endField)
    var timezone = timezoneField.text.trim()
    if (title === "") {
      errorText = "An event title is required."
      titleField.forceActiveFocus()
      return
    }
    if (startAt === false || endAt === false) {
      errorText = "Start and end must be ISO dates, for example 2026-09-04T10:00:00+02:00."
      startField.forceActiveFocus()
      return
    }
    if (new Date(endAt) <= new Date(startAt)) {
      errorText = "The event must end after it starts."
      endField.forceActiveFocus()
      return
    }
    if (timezone === "") {
      errorText = "An IANA timezone is required, for example Europe/Rome."
      timezoneField.forceActiveFocus()
      return
    }

    var input = {
      title: title,
      description: descriptionField.text,
      startAt: startAt,
      endAt: endAt,
      timezone: timezone,
      allDay: root.allDay,
      rrule: recurrenceField.text.trim() === "" ? null : recurrenceField.text.trim()
    }
    var result = root.event
      ? root.service.updateEvent(root.event.id, input)
      : root.service.addEvent(input)
    if (result) root.saved()
    else errorText = root.service ? root.service.lastSolverError : "The event could not be saved."
  }

  Component.onCompleted: {
    reset()
    Qt.callLater(function() { titleField.forceActiveFocus() })
  }
  onEventChanged: reset()

  Rectangle {
    anchors.fill: parent
    color: Color.popups.background
    border.width: Style.spacing.hairline
    border.color: Color.popups.border
    radius: Style.cornerRadius
  }

  Flickable {
    id: scroll
    anchors.fill: parent
    anchors.margins: Style.space(18)
    contentWidth: form.width
    contentHeight: form.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Column {
      id: form
      width: Math.max(scroll.width, Style.space(390))
      spacing: Style.space(10)

      Text {
        textFormat: Text.PlainText
        text: root.event ? "Edit event" : "Add event"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        text: "Manual events are busy time for the planner."
        color: Qt.darker(root.foreground, 1.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text { textFormat: Text.PlainText; text: "Title"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
      TextField {
        id: titleField
        width: parent.width
        enabled: root.manualEvent
        foreground: root.foreground
        font.family: root.fontFamily
        placeholderText: "Meeting, appointment, or personal block"
        Keys.onReturnPressed: root.save()
        Keys.onEscapePressed: root.cancelled()
      }

      Row {
        width: parent.width
        spacing: Style.space(10)
        Column {
          width: (parent.width - Style.space(10)) / 2
          spacing: Style.spacing.labelGap
          Text { textFormat: Text.PlainText; text: "Starts"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          TextField {
            id: startField
            width: parent.width
            enabled: root.manualEvent
            foreground: root.foreground
            font.family: root.fontFamily
            placeholderText: "2026-09-04T10:00:00+02:00"
            Keys.onEscapePressed: root.cancelled()
          }
        }
        Column {
          width: (parent.width - Style.space(10)) / 2
          spacing: Style.spacing.labelGap
          Text { textFormat: Text.PlainText; text: "Ends"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          TextField {
            id: endField
            width: parent.width
            enabled: root.manualEvent
            foreground: root.foreground
            font.family: root.fontFamily
            placeholderText: "2026-09-04T11:00:00+02:00"
            Keys.onReturnPressed: Qt.callLater(root.save)
            Keys.onEscapePressed: root.cancelled()
          }
        }
      }

      Text { textFormat: Text.PlainText; text: "Timezone"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
      TextField {
        id: timezoneField
        width: parent.width
        enabled: root.manualEvent
        foreground: root.foreground
        font.family: root.fontFamily
        placeholderText: "Europe/Rome"
        Keys.onEscapePressed: root.cancelled()
      }

      Row {
        width: parent.width
        spacing: Style.space(10)
        Text {
          textFormat: Text.PlainText
          text: "All day"
          anchors.verticalCenter: parent.verticalCenter
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
        ToggleSwitch {
          checked: root.allDay
          enabled: root.manualEvent
          foreground: root.foreground
          onToggled: root.allDay = !root.allDay
        }
      }

      Text { textFormat: Text.PlainText; text: "Description (optional)"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
      TextField {
        id: descriptionField
        width: parent.width
        enabled: root.manualEvent
        foreground: root.foreground
        font.family: root.fontFamily
        placeholderText: "Notes"
      }

      Text { textFormat: Text.PlainText; text: "RRULE recurrence (optional)"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
      TextField {
        id: recurrenceField
        width: parent.width
        enabled: root.manualEvent
        foreground: root.foreground
        font.family: root.fontFamily
        placeholderText: "FREQ=WEEKLY;BYDAY=MO"
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

      Row {
        spacing: Style.space(8)
        Button {
          focusable: true
          visible: root.manualEvent
          text: "Save event"
          foreground: Color.background
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
        Button {
          focusable: true
          visible: root.event !== null && root.event.origin === "planner" && !!root.event.taskId
          text: "Return to inbox"
          foreground: root.foreground
          bordered: true
          fontFamily: root.fontFamily
          onClicked: {
            var result = root.service ? root.service.returnToInbox(root.event.taskId) : null
            if (result) root.saved()
            else root.errorText = root.service ? root.service.lastSolverError : "The task could not be returned to the inbox."
          }
        }
        Button {
          focusable: true
          visible: root.event !== null && root.event.origin === "manual"
          text: "Delete event"
          foreground: Color.urgent
          bordered: true
          fontFamily: root.fontFamily
          onClicked: {
            var result = root.service ? root.service.deleteEvent(root.event.id) : null
            if (result) root.saved()
            else root.errorText = root.service ? root.service.lastSolverError : "The event could not be deleted."
          }
        }
      }
    }
  }
}
