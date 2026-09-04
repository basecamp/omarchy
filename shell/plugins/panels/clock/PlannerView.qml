import QtQuick
import qs.Commons
import qs.Ui
import "."
import "PlannerModel.js" as PlannerModel

Item {
  id: root

  property var service: null
  property var bar: null
  property string activeView: "plan"
  property string editorMode: ""
  property var editorEvent: null
  property var editorTask: null
  property color foreground: bar ? bar.foreground : Color.foreground
  property string fontFamily: bar ? bar.fontFamily : Style.font.family
  signal calendarRequested()
  signal addTaskRequested()
  signal settingsRequested()
  signal reviewProposalRequested()

  implicitHeight: contentColumn.implicitHeight + Style.space(24)

  function state() {
    return root.service && root.service.calendarState
      ? root.service.calendarState
      : { settings: {}, events: [], tasks: [], proposal: null }
  }

  function proposal() { return state().proposal }
  function proposalSummary() { return PlannerModel.proposalSummary(proposal()) }

  function openEditor(mode, value) {
    root.editorEvent = mode === "event" ? value : null
    root.editorTask = mode === "task" ? value : null
    root.editorMode = mode
  }

  function closeEditor() {
    root.editorMode = ""
    root.editorEvent = null
    root.editorTask = null
  }

  function cancelEditor() {
    root.closeEditor()
  }

  function focusFirst() {
    if (root.editorMode === "") addTaskButton.forceActiveFocus()
  }

  Keys.onEscapePressed: {
    if (root.editorMode !== "") root.cancelEditor()
    else root.calendarRequested()
  }

  Flickable {
    id: scroll
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: contentColumn.width
    contentHeight: contentColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Column {
      id: contentColumn
      width: Math.max(scroll.width, Style.space(390))
      spacing: Style.space(14)

      Item {
        width: parent.width
        height: titleColumn.implicitHeight

        Column {
          id: titleColumn
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.space(4)

          Text {
            textFormat: Text.PlainText
            text: root.activeView === "agenda" ? "Agenda" : "Planner inbox"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            text: root.activeView === "agenda"
              ? "Your native calendar and applied schedule"
              : root.service && root.service.configured
                ? "Suggestions are automatic; your calendar changes only when you apply them."
                : (root.service ? root.service.setupMessage : "Planner service is loading.")
            color: Qt.darker(root.foreground, 1.45)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            width: parent.width
          }
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        Button {
          focusable: true
          id: addTaskButton
          text: "+ Add task"
          foreground: Color.background
          background: Color.accent
          fontFamily: root.fontFamily
          onClicked: root.openEditor("task", null)
        }

        Button {
          focusable: true
          visible: root.activeView === "agenda"
          text: "+ Event"
          foreground: Color.background
          background: Color.accent
          fontFamily: root.fontFamily
          onClicked: root.openEditor("event", null)
        }

        Button {
          focusable: true
          visible: root.activeView === "plan"
          text: "Settings"
          foreground: root.foreground
          bordered: true
          fontFamily: root.fontFamily
          onClicked: root.openEditor("settings", null)
        }
      }

      AgendaView {
        visible: root.activeView === "agenda"
        width: parent.width
        service: root.service
        bar: root.bar
        onAddEventRequested: root.openEditor("event", null)
        onEditEventRequested: function(event) { root.openEditor("event", event) }
      }

      Column {
        visible: root.activeView === "plan"
        width: parent.width
        spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          visible: root.service && root.service.solveState === "solving"
          text: "Finding a schedule…"
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Repeater {
          model: PlannerModel.sortedTasks(root.state().tasks.filter(function(task) { return task.state === "inbox" }))
          delegate: Rectangle {
            required property var modelData
            width: parent.width
            height: taskText.implicitHeight + Style.space(18)
            radius: Style.cornerRadius
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

            Column {
              id: taskText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(3)
              Row {
                width: parent.width
                spacing: Style.space(8)
                Text {
                  textFormat: Text.PlainText
                  text: modelData.title
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                  width: parent.width - duration.implicitWidth - spacing
                }
                Text {
                  textFormat: Text.PlainText
                  id: duration
                  text: PlannerModel.formatDuration(modelData.durationMinutes)
                  color: Qt.darker(root.foreground, 1.45)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
                Button {
                  focusable: true
                  text: "Edit"
                  foreground: root.foreground
                  bordered: true
                  fontFamily: root.fontFamily
                  onClicked: root.openEditor("task", modelData)
                }
              }
              Text {
                textFormat: Text.PlainText
                text: PlannerModel.priorityLabel(modelData.priority) + " · "
                  + PlannerModel.loadLabel(modelData.cognitiveLoad) + " · "
                  + PlannerModel.formatDeadline(modelData.deadlineAt, root.state().settings.timezone)
                color: Qt.darker(root.foreground, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.state().tasks.filter(function(task) { return task.state === "inbox" }).length === 0
          text: "No tasks in the inbox."
          color: Qt.darker(root.foreground, 1.45)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Rectangle {
          visible: root.proposal() !== null
          width: parent.width
          height: proposalText.implicitHeight + Style.space(24)
          radius: Style.cornerRadius
          color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.10)
          border.width: Style.spacing.hairline
          border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.45)

          Column {
            id: proposalText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(4)
            Text {
              textFormat: Text.PlainText
              text: "Latest proposal"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              text: {
                var summary = root.proposalSummary()
                return summary.scheduled + " of " + summary.total + " inbox tasks scheduled"
              }
              color: Qt.darker(root.foreground, 1.3)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              textFormat: Text.PlainText
              text: root.service && root.service.solveState === "ready"
                ? "Ready to review — the calendar is unchanged."
                : (root.service ? root.service.lastSolverError : "")
              color: root.service && root.service.solveState === "error" ? Color.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              width: parent.width
            }
            Button {
              focusable: true
              text: "Review proposal"
              foreground: Color.background
              background: Color.accent
              fontFamily: root.fontFamily
              onClicked: root.openEditor("proposal", null)
            }
          }
        }
      }
    }
  }

  Loader {
    id: editorLoader
    anchors.fill: parent
    active: root.editorMode !== ""
    source: root.editorMode === "task"
      ? Qt.resolvedUrl("TaskEditor.qml")
      : root.editorMode === "event"
        ? Qt.resolvedUrl("EventEditor.qml")
        : root.editorMode === "settings"
          ? Qt.resolvedUrl("PlannerSettings.qml")
          : Qt.resolvedUrl("ProposalReview.qml")
    onLoaded: {
      item.service = root.service
      item.bar = root.bar
      if (root.editorMode === "task") item.task = root.editorTask
      if (root.editorMode === "event") item.event = root.editorEvent
    }
  }

  Connections {
    target: editorLoader.item
    function onSaved() { root.closeEditor() }
    function onCancelled() { root.closeEditor() }
  }

  onServiceChanged: if (editorLoader.item) editorLoader.item.service = root.service
  onBarChanged: if (editorLoader.item) editorLoader.item.bar = root.bar
  onEditorModeChanged: if (root.editorMode === "") Qt.callLater(root.focusFirst)
}
