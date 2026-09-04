import QtQuick
import qs.Commons
import qs.Ui
import "PlannerModel.js" as PlannerModel

// Proposal review is the explicit commit boundary. It displays every solver
// item, including unscheduled explanations, and never changes the calendar
// until Apply is pressed.
Item {
  id: root

  property var service: null
  property var bar: null
  property color foreground: bar ? bar.foreground : Color.foreground
  property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property string message: ""
  signal cancelled()

  function state() {
    return root.service && root.service.calendarState
      ? root.service.calendarState
      : { settings: {}, tasks: [], proposal: null }
  }

  function proposal() { return state().proposal }

  function taskFor(id) {
    var tasks = state().tasks || []
    for (var i = 0; i < tasks.length; i++) if (tasks[i].id === id) return tasks[i]
    return { title: id, durationMinutes: 0 }
  }

  function currentReady() {
    var value = proposal()
    return value && value.status === "ready" && Number(value.baseInputRevision) === state().inputRevision
  }

  function applicabilityReasons() {
    return PlannerModel.applicabilityReasons(root.proposal(), state().inputRevision)
  }

  function apply() {
    var result = root.service ? root.service.applyProposal() : null
    if (result) root.message = "Applied. Planner events are now on the calendar."
    else root.message = root.service ? root.service.lastSolverError : "The proposal could not be applied."
  }

  Component.onCompleted: Qt.callLater(function() { applyButton.forceActiveFocus() })

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
      spacing: Style.space(9)

      Row {
        width: parent.width
        Text {
          textFormat: Text.PlainText
          width: parent.width - closeButton.width
          text: "Review proposal"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.display
          font.bold: true
        }
        Button {
          focusable: true
          id: closeButton
          text: "Close"
          foreground: root.foreground
          bordered: true
          fontFamily: root.fontFamily
          onClicked: root.cancelled()
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.proposal() !== null
        text: {
          var summary = PlannerModel.proposalSummary(root.proposal())
          return summary.scheduled + " scheduled · " + summary.unscheduled + " still in the inbox"
            + " · " + (root.proposal().timezone || "")
        }
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
      Text {
        textFormat: Text.PlainText
        visible: root.proposal() === null
        text: "No proposal is available yet. Add an inbox task and configure planning settings."
        color: Qt.darker(root.foreground, 1.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        width: parent.width
      }

      Column {
        visible: root.proposal() !== null && root.applicabilityReasons().length > 0
        width: parent.width
        spacing: Style.space(3)
        Repeater {
          model: root.applicabilityReasons()
          delegate: Text {
            required property string modelData
            textFormat: Text.PlainText
            text: modelData
            color: root.currentReady() ? Qt.darker(root.foreground, 1.4) : Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            width: parent.width
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.proposal() !== null
        text: "Scheduled"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Repeater {
        model: PlannerModel.scheduledItems(root.proposal())
        delegate: Rectangle {
          required property var modelData
          width: form.width
          height: scheduledColumn.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

          Column {
            id: scheduledColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(3)
            Text {
              textFormat: Text.PlainText
              text: root.taskFor(modelData.taskId).title
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
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
              text: "Priority " + PlannerModel.priorityLabel(root.taskFor(modelData.taskId).priority)
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Button {
              focusable: true
              text: "Return to inbox"
              foreground: root.foreground
              bordered: true
              fontFamily: root.fontFamily
              onClicked: root.service.returnToInbox(modelData.taskId)
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.proposal() !== null && PlannerModel.scheduledItems(root.proposal()).length === 0
        text: "No task received a feasible slot."
        color: Qt.darker(root.foreground, 1.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        textFormat: Text.PlainText
        visible: root.proposal() !== null
        text: "Unscheduled and diagnostics"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Repeater {
        model: PlannerModel.unscheduledItems(root.proposal())
        delegate: Rectangle {
          required property var modelData
          width: form.width
          height: unscheduledColumn.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.08)

          Column {
            id: unscheduledColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(3)
            Text {
              textFormat: Text.PlainText
              text: root.taskFor(modelData.taskId).title
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              text: PlannerModel.outcomeLabel(modelData)
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              textFormat: Text.PlainText
              text: PlannerModel.explanation(modelData)
              color: Qt.darker(root.foreground, 1.35)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              width: parent.width
            }
            Text {
              textFormat: Text.PlainText
              text: {
                var penalty = PlannerModel.penaltySummary(modelData)
                return "Penalties · cognitive " + penalty.cognitive + " · fatigue " + penalty.fatigue
              }
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.message !== ""
        text: root.message
        color: root.currentReady() ? root.foreground : Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        width: parent.width
      }

      Button {
        focusable: true
        id: applyButton
        text: "Apply schedule"
        enabled: root.currentReady()
        foreground: Color.background
        background: Color.accent
        fontFamily: root.fontFamily
        onClicked: root.apply()
      }
    }
  }
}
