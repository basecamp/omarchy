import QtQuick
import QtQuick.Controls
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
  readonly property real editorImplicitHeight: editorLoader.item && Number(editorLoader.item.implicitHeight) > 0
    ? Number(editorLoader.item.implicitHeight)
    : 0
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
  function showProposal() {
    var value = root.proposal()
    return value !== null && root.service && root.service.hasInboxTasks
  }

  function planningFlow() {
    if (!root.service || !root.service.configured)
      return "1  Open Settings and choose your timezone and weekly availability.  2  Add a planning task.  3  Plan tasks, review the suggestion, and apply it."
    if (!root.service.hasInboxTasks)
      return "1  Add a planning task.  2  Choose Plan tasks.  3  Review the suggested schedule, then apply it."
    return "1  Add or edit tasks.  2  Choose Plan tasks.  3  Review the suggested schedule, then apply it. The calendar changes only when you apply."
  }

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
    if (root.editorMode !== "") return
    if (root.activeView === "agenda") agendaEventButton.forceActiveFocus()
    else addTaskButton.forceActiveFocus()
  }

  Keys.onEscapePressed: {
    if (root.editorMode !== "") root.cancelEditor()
    else root.calendarRequested()
  }

  ScrollView {
    id: scroll
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: contentColumn.width
    contentHeight: contentColumn.implicitHeight
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    ScrollBar.vertical.policy: contentColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

    Column {
      id: contentColumn
      width: scroll.availableWidth
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
              ? "Events are fixed calendar time; tasks to schedule live in Plan."
              : root.service && root.service.configured
                ? "Tasks are work to schedule. Events are fixed busy time. Apply Omarchy's suggested schedule when you are ready."
                : (root.service ? root.service.setupMessage + " Tasks are work to schedule; events are fixed busy time." : "Planner service is loading.")
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
          visible: root.activeView === "plan"
          text: "Add planning task"
          foreground: activeFocus || hot ? Color.foreground : Color.background
          background: Color.accent
          fontFamily: root.fontFamily
          onClicked: root.openEditor("task", null)
        }

        Button {
          focusable: true
          id: planTasksButton
          visible: root.activeView === "plan"
          enabled: !!root.service && root.service.solveState !== "solving"
          text: root.service && root.service.solveState === "solving" ? "Planning…" : "Plan tasks"
          foreground: activeFocus || hot ? Color.foreground : Color.background
          background: Color.accent
          fontFamily: root.fontFamily
          onClicked: if (root.service) root.service.planNow()
        }

        Button {
          focusable: true
          id: agendaEventButton
          visible: root.activeView === "agenda"
          text: "Add calendar event"
          foreground: activeFocus || hot ? Color.foreground : Color.background
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

      Rectangle {
        visible: root.activeView === "plan"
        width: parent.width
        height: flowColumn.implicitHeight + Style.space(20)
        radius: Style.cornerRadius
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

        Column {
          id: flowColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          spacing: Style.space(4)

          Text {
            textFormat: Text.PlainText
            text: "How planning works"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            textFormat: Text.PlainText
            text: root.planningFlow()
            color: Qt.darker(root.foreground, 1.35)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            width: parent.width
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.activeView === "plan" && root.service && root.service.lastSolverError !== ""
        text: root.service ? root.service.lastSolverError : ""
        color: Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        width: parent.width
      }

      AgendaView {
        visible: root.activeView === "agenda"
        width: parent.width
        service: root.service
        bar: root.bar
        onEditEventRequested: function(event) { root.openEditor("event", event) }
      }

      Column {
        visible: root.activeView === "plan"
        width: parent.width
        spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          visible: root.service && root.service.solveState === "solving"
          text: "Omarchy is planning your tasks…"
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
                  width: parent.width - duration.implicitWidth - parent.spacing
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
          visible: root.showProposal()
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
              text: "Suggested schedule"
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
                ? "Ready to review — the calendar is unchanged until you apply."
                : (root.service ? root.service.lastSolverError : "")
              color: root.service && root.service.solveState === "error" ? Color.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              width: parent.width
            }
            Button {
              focusable: true
              text: "Review schedule"
              foreground: activeFocus || hot ? Color.foreground : Color.background
              background: Color.accent
              fontFamily: root.fontFamily
              onClicked: if (root.showProposal()) root.openEditor("proposal", null)
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
      if (root.editorMode === "task" && "task" in item) item.task = root.editorTask
      if (root.editorMode === "event" && "event" in item) item.event = root.editorEvent
    }
  }

  Connections {
    ignoreUnknownSignals: true
    target: editorLoader.item && (("saved" in editorLoader.item) || ("cancelled" in editorLoader.item))
      ? editorLoader.item
      : null
    function onSaved() { root.closeEditor() }
    function onCancelled() { root.closeEditor() }
  }

  onServiceChanged: if (editorLoader.item) editorLoader.item.service = root.service
  onBarChanged: if (editorLoader.item) editorLoader.item.bar = root.bar
  onEditorModeChanged: if (root.editorMode === "") Qt.callLater(root.focusFirst)
  onActiveViewChanged: if (root.editorMode === "") Qt.callLater(root.focusFirst)
}
