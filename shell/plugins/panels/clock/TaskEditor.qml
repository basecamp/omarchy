import QtQuick
import qs.Commons
import qs.Ui
import "."

// Small, keyboard-friendly editor for an inbox task. The editor deliberately
// emits no state of its own: Service.qml remains the only owner and the
// reducer decides whether a submitted value is valid.
Item {
  id: root

  property var service: null
  property var bar: null
  property var task: null
  property color foreground: bar ? bar.foreground : Color.foreground
  property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property string errorText: ""
  property string priority: "normal"
  property string cognitiveLoad: "medium"
  property string deadlineKind: "none"
  property string earliestAt: ""
  property string deadlineAt: ""
  property var dependencyIds: []
  property int durationMinutes: 30

  signal saved()
  signal cancelled()

  // The popup sizes itself from the form. The viewport is deliberately not a
  // scrolling input surface: Save and Cancel stay visible as the form grows.
  implicitHeight: form.implicitHeight + Style.space(36)

  function reset() {
    var value = root.task || {}
    titleField.text = value.title || ""
    durationMinutes = Number(value.durationMinutes || 30)
    priority = value.priority || "normal"
    cognitiveLoad = value.cognitiveLoad || "medium"
    root.earliestAt = value.earliestAt || ""
    deadlineKind = value.deadlineKind || "none"
    root.deadlineAt = value.deadlineAt || ""
    dependencyIds = predecessorsFor(value.id || "")
    errorText = ""
  }

  function predecessorsFor(taskId) {
    if (!root.service || !taskId) return []
    var result = []
    var dependencies = root.service.calendarState.dependencies || []
    for (var i = 0; i < dependencies.length; i++)
      if (dependencies[i].toTaskId === taskId) result.push(dependencies[i].fromTaskId)
    return result
  }

  function dependencyOptions() {
    if (!root.service) return []
    var tasks = root.service.calendarState.tasks || []
    var result = []
    for (var i = 0; i < tasks.length; i++) {
      if (root.task && tasks[i].id === root.task.id) continue
      result.push({ value: tasks[i].id, label: tasks[i].title, description: tasks[i].state })
    }
    return result
  }

  function save() {
    var title = titleField.text.trim()
    if (title === "") {
      errorText = "A task title is required."
      titleField.forceActiveFocus()
      return
    }

    var earliest = earliestField.valid ? root.earliestAt || null : false
    var deadline = deadlineKind === "none" ? null : (deadlineField.valid ? root.deadlineAt || null : false)
    if (earliest === false) {
      errorText = "Choose an earliest date and enter its time as HH:MM."
      earliestField.forceActiveFocus()
      return
    }
    if (deadline === false || (deadlineKind !== "none" && deadline === null)) {
      errorText = "Choose a deadline date and enter its time as HH:MM."
      deadlineField.forceActiveFocus()
      return
    }

    var input = {
      title: title,
      durationMinutes: durationMinutes,
      priority: priority,
      cognitiveLoad: cognitiveLoad,
      earliestAt: earliest,
      deadlineKind: deadlineKind,
      deadlineAt: deadline
    }
    var result = root.task
      ? root.service.updateTask(root.task.id, input)
      : root.service.addTask(input)
    if (!result) {
      errorText = root.service ? root.service.lastSolverError : "The task could not be saved."
      return
    }
    var savedTaskId = root.task ? root.task.id : result.tasks[result.tasks.length - 1].id
    var dependencies = root.service.replaceTaskDependencies(savedTaskId, root.dependencyIds)
    // The reducer returns the full state. For a newly-added task the last
    // task is the one just created; existing edits retain their id.
    if (dependencies) root.saved()
    else errorText = root.service.lastSolverError
  }

  Component.onCompleted: {
    reset()
    Qt.callLater(function() { titleField.forceActiveFocus() })
  }
  onTaskChanged: reset()

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
        text: root.task ? "Edit planning task" : "Add planning task"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
        font.bold: true
      }

      Text {
        textFormat: Text.PlainText
        text: "A planning task is work Omarchy may schedule. Calendar events are fixed busy time. Tasks stay in the inbox until you apply a schedule."
        color: Qt.darker(root.foreground, 1.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        width: parent.width
      }

      Text { textFormat: Text.PlainText; text: "Title"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
      TextField {
        id: titleField
        width: parent.width
        foreground: root.foreground
        font.family: root.fontFamily
        placeholderText: "Write the next actionable task"
        Keys.onReturnPressed: root.save()
        Keys.onEscapePressed: root.cancelled()
      }

      Row {
        width: parent.width
        spacing: Style.space(10)

        NumberField {
          label: "Duration (minutes)"
          width: Style.space(150)
          value: root.durationMinutes
          from: 5
          to: 1440
          stepSize: 5
          foreground: root.foreground
          onModified: root.durationMinutes = value
        }

        Dropdown {
          width: Style.space(140)
          label: "Priority"
          value: root.priority
          options: [
            { value: "low", label: "Low" },
            { value: "normal", label: "Normal" },
            { value: "high", label: "High" }
          ]
          foreground: root.foreground
          onChanged: root.priority = value
        }

        Dropdown {
          width: Style.space(150)
          label: "Cognitive load"
          value: root.cognitiveLoad
          options: [
            { value: "low", label: "Low" },
            { value: "medium", label: "Medium" },
            { value: "high", label: "High" }
          ]
          foreground: root.foreground
          onChanged: root.cognitiveLoad = value
        }
      }

      PlannerDateTimeField {
        id: earliestField
        width: parent.width
        label: "Earliest start (optional)"
        value: root.earliestAt
        allowEmpty: true
        emptyLabel: "No earliest time"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onChanged: function(next) { root.earliestAt = next }
        onCancelled: root.cancelled()
      }

      Row {
        width: parent.width
        spacing: Style.space(10)
        Dropdown {
          width: Style.space(150)
          label: "Deadline"
          value: root.deadlineKind
          options: [
            { value: "none", label: "None" },
            { value: "soft", label: "Soft" },
            { value: "hard", label: "Hard" }
          ]
          foreground: root.foreground
          onChanged: root.deadlineKind = value
        }
          PlannerDateTimeField {
            id: deadlineField
            width: parent.width - Style.space(160)
            label: "Deadline time"
            value: root.deadlineAt
            allowEmpty: true
            emptyLabel: "No deadline"
            enabled: root.deadlineKind !== "none"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function(next) { root.deadlineAt = next }
            onCancelled: root.cancelled()
        }
      }

      MultiSelect {
        label: "Depends on"
        width: parent.width
        values: root.dependencyIds
        options: root.dependencyOptions()
        foreground: root.foreground
        onChanged: function(next) { root.dependencyIds = next }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.errorText !== ""
        text: root.errorText
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
          text: "Save task"
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
          visible: root.task !== null
          text: "Delete task"
          foreground: Color.urgent
          bordered: true
          fontFamily: root.fontFamily
          onClicked: {
            var result = root.service ? root.service.deleteTask(root.task.id) : null
            if (result) root.saved()
            else root.errorText = root.service ? root.service.lastSolverError : "The task could not be deleted."
          }
        }
      }
    }
  }
}
