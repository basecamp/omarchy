import QtQuick
import qs.Commons
import qs.Ui
import "."

// Manual event editor. Dates are picked visually and converted to ISO-8601
// only at the state boundary, so users never need to type a timestamp.
Item {
  id: root

  property var service: null
  property var bar: null
  property var event: null
  property color foreground: bar ? bar.foreground : Color.foreground
  property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property string errorText: ""
  property bool allDay: false
  property string startAt: ""
  property string endAt: ""
  readonly property bool manualEvent: !root.event || root.event.origin === "manual"

  signal saved()
  signal cancelled()

  // The popup sizes itself from the form. The viewport is deliberately not a
  // scrolling input surface: Save and Cancel stay visible as the form grows.
  implicitHeight: form.implicitHeight + Style.space(36)

  function defaultTimezone() {
    if (root.service && root.service.calendarState.settings.timezone)
      return root.service.calendarState.settings.timezone
    try { return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC" }
    catch (error) { return "UTC" }
  }

  function reset() {
    var value = root.event || {}
    titleField.text = value.title || ""
    var start = value.startAt ? new Date(value.startAt) : new Date()
    var end = value.endAt ? new Date(value.endAt) : new Date(start.getTime() + 60 * 60 * 1000)
    root.startAt = value.startAt || start.toISOString()
    root.endAt = value.endAt || end.toISOString()
    timezoneField.text = value.timezone || defaultTimezone()
    descriptionField.text = value.description || ""
    recurrenceField.text = value.rrule || ""
    allDay = !!value.allDay
    errorText = ""
  }

  function save() {
    if (!root.manualEvent) {
      errorText = "Applied planner events are changed through the planner. Return the task to the inbox first."
      return
    }
    var title = titleField.text.trim()
    var startAt = startAtField.valid ? root.startAt : false
    var endAt = endAtField.valid ? root.endAt : false
    var timezone = timezoneField.text.trim()
    if (title === "") {
      errorText = "An event title is required."
      titleField.forceActiveFocus()
      return
    }
    if (startAt === false || endAt === false) {
      errorText = "Choose a start and end date, then enter each time as HH:MM."
      if (!startAtField.valid) startAtField.forceActiveFocus()
      else endAtField.forceActiveFocus()
      return
    }
    if (new Date(endAt) <= new Date(startAt)) {
      errorText = "The event must end after it starts."
      endAtField.forceActiveFocus()
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
  // PlannerView injects the service immediately after this editor is loaded.
  // Reset once more so a new event picks up Omarchy's configured timezone
  // instead of the local UTC fallback used during construction.
  onServiceChanged: root.reset()
  onEventChanged: reset()

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

    Column {
      id: form
      width: Math.max(viewport.width, Style.space(390))
      spacing: Style.space(10)

      Text {
        textFormat: Text.PlainText
        text: root.event ? "Edit calendar event" : "Add calendar event"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        text: "A calendar event is fixed busy time. Planning tasks are added from Plan."
        color: Qt.darker(root.foreground, 1.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text { textFormat: Text.PlainText; text: "Title"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
      TextField {
        id: titleField
        width: parent.width
        activeFocusOnTab: true
        KeyNavigation.tab: startAtField.dateFocusTarget
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
          PlannerDateTimeField {
            id: startAtField
            width: parent.width
            enabled: root.manualEvent
            label: "Starts"
            value: root.startAt
            nextFocusTarget: endAtField.dateFocusTarget
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function(next) { root.startAt = next }
            onSubmitted: root.save()
            onCancelled: root.cancelled()
          }
        }
        Column {
          width: (parent.width - Style.space(10)) / 2
          spacing: Style.spacing.labelGap
          PlannerDateTimeField {
            id: endAtField
            width: parent.width
            enabled: root.manualEvent
            label: "Ends"
            value: root.endAt
            nextFocusTarget: timezoneField
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function(next) { root.endAt = next }
            onSubmitted: root.save()
            onCancelled: root.cancelled()
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
