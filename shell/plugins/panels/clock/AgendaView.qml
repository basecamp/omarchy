import QtQuick
import qs.Commons
import qs.Ui
import "PlannerModel.js" as PlannerModel

// Reusable agenda surface for the planner tab. Panel.qml keeps the original
// month grid untouched; this component owns the event-oriented view beside it.
Item {
  id: root

  property var service: null
  property var bar: null
  property color foreground: bar ? bar.foreground : Color.foreground
  property string fontFamily: bar ? bar.fontFamily : Style.font.family
  signal addEventRequested()
  signal editEventRequested(var event)

  implicitHeight: content.implicitHeight

  function state() {
    return root.service && root.service.calendarState
      ? root.service.calendarState
      : { settings: {}, events: [] }
  }

  function dayKeys() {
    var settings = state().settings || {}
    var timezone = settings.timezone || ""
    var grouped = PlannerModel.eventsByDay(state().events, timezone)
    var today = PlannerModel.dayKey(new Date(), timezone)
    var horizonDays = Math.max(1, Number(settings.horizonDays) || 14)
    var end = PlannerModel.dayKey(new Date(Date.now() + horizonDays * 86400000), timezone)
    return Object.keys(grouped).filter(function(key) { return key >= today && key <= end }).sort()
  }

  Column {
    id: content
    width: parent.width
    spacing: Style.space(6)

    Row {
      width: parent.width
      Text {
        textFormat: Text.PlainText
        width: parent.width - addButton.width
        text: "Agenda"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
        font.bold: true
      }
      Button {
        focusable: true
        id: addButton
        text: "+ Event"
        foreground: Color.background
        background: Color.accent
        fontFamily: root.fontFamily
        onClicked: root.addEventRequested()
      }
    }

    Repeater {
      model: root.dayKeys()
      delegate: Column {
        required property string modelData
        property string dayKey: modelData
        width: content.width
        spacing: Style.space(5)

        Text {
          textFormat: Text.PlainText
          text: dayKey
          color: Qt.darker(root.foreground, 1.35)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }

        Repeater {
          model: PlannerModel.eventsForDay(root.state().events, dayKey, root.state().settings.timezone)
          delegate: Rectangle {
            required property var modelData
            width: content.width
            height: eventColumn.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

            Column {
              id: eventColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(3)
              Row {
                width: parent.width
                Button {
                  focusable: true
                  id: eventAction
                  visible: modelData.origin === "manual" || !!modelData.taskId
                  text: modelData.origin === "manual" ? "Edit" : "Return to inbox"
                  foreground: root.foreground
                  bordered: true
                  fontFamily: root.fontFamily
                  onClicked: {
                    if (modelData.origin === "manual") root.editEventRequested(modelData)
                    else root.service.returnToInbox(modelData.taskId)
                  }
                }
                Text {
                  textFormat: Text.PlainText
                  width: parent.width - (eventAction.visible ? eventAction.width : 0) - Style.space(8)
                  text: modelData.title
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }
              }
              Text {
                textFormat: Text.PlainText
                text: Qt.formatDateTime(new Date(modelData.startAt), "ddd d MMM  HH:mm")
                  + " — " + Qt.formatDateTime(new Date(modelData.endAt), "HH:mm")
                color: Qt.darker(root.foreground, 1.35)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                textFormat: Text.PlainText
                visible: modelData.origin !== "manual"
                text: "Planner event linked to task"
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                textFormat: Text.PlainText
                visible: modelData.description !== ""
                text: modelData.description
                color: Qt.darker(root.foreground, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
                width: parent.width
              }
            }
          }
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: root.dayKeys().length === 0
      text: "No events yet."
      color: Qt.darker(root.foreground, 1.45)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
