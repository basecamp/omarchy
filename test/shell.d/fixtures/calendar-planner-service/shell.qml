import QtQuick
import Quickshell

ShellRoot {
  id: root

  property string resultPath: Quickshell.env("OMARCHY_QML_TEST_RESULT")
  property string serviceUrl: Quickshell.env("OMARCHY_QML_SERVICE_URL")
  property var failures: []
  property var service: null
  property string firstTaskId: ""
  property string secondTaskId: ""
  property int phase: 0

  function fail(message) { root.failures.push(String(message)) }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function writeResult() {
    var payload = JSON.stringify({ ok: root.failures.length === 0, failures: root.failures })
    Quickshell.execDetached([
      "bash", "-lc",
      "printf '%s' " + root.shellQuote(payload) + " > " + root.shellQuote(root.resultPath)
    ])
  }

  function start() {
    var component = Qt.createComponent(root.serviceUrl, Component.PreferSynchronous)
    if (component.status !== Component.Ready) {
      root.fail("service component failed to load: " + component.errorString())
      root.writeResult()
      return
    }
    root.service = component.createObject(host)
    if (!root.service) {
      root.fail("service component failed to instantiate")
      root.writeResult()
      return
    }
    poll.start()
  }

  function item(taskId) {
    var proposal = root.service.calendarState.proposal
    var items = proposal && proposal.items || []
    for (var i = 0; i < items.length; i++) if (items[i].taskId === taskId) return items[i]
    return null
  }

  function advance() {
    if (!root.service || !root.service.stateLoaded) return

    if (root.phase === 0) {
      if (root.service.solveState !== "configuration_needed") {
        root.fail("first-run service state should require configuration")
        root.phase = 99
        root.writeResult()
        return
      }
      if (!root.service.updateSettings({
        timezone: "Europe/Rome",
        availability: { friday: [{ start: "09:00", end: "17:00" }] }
      })) {
        root.fail("service rejected valid first-run settings")
        root.phase = 99
        root.writeResult()
        return
      }
      var first = root.service.addTask({
        title: "Service integration task", durationMinutes: 30, priority: "high",
        cognitiveLoad: "medium", deadlineKind: "none", deadlineAt: null, earliestAt: null
      })
      var second = root.service.addTask({
        title: "Dependent integration task", durationMinutes: 30, priority: "normal",
        cognitiveLoad: "medium", deadlineKind: "none", deadlineAt: null, earliestAt: null
      })
      root.firstTaskId = first.tasks[first.tasks.length - 1].id
      root.secondTaskId = second.tasks[second.tasks.length - 1].id
      if (!root.service.addDependency(root.firstTaskId, root.secondTaskId)) {
        root.fail("service rejected a valid dependency")
        root.phase = 99
        root.writeResult()
        return
      }
      root.phase = 1
      return
    }

    if (root.phase === 1) {
      var proposal = root.service.calendarState.proposal
      if (root.service.solveState !== "ready" || !proposal || Number(proposal.baseInputRevision) !== root.service.calendarState.inputRevision) return
      var firstItem = root.item(root.firstTaskId)
      var secondItem = root.item(root.secondTaskId)
      if (!firstItem || !firstItem.scheduled) root.fail("in-process planner scheduled the prerequisite task")
      if (!secondItem || !secondItem.scheduled) root.fail("in-process planner scheduled the dependent task")
      if (firstItem && secondItem && Date.parse(firstItem.endAt) > Date.parse(secondItem.startAt)) root.fail("in-process planner respected dependency order")
      if (root.service.calendarState.events.length !== 0) root.fail("proposal changed events before Apply")
      if (!root.service.updateTask(root.firstTaskId, { title: "Updated integration task" })) root.fail("service rejected an input update")
      if (!root.service.planNow()) root.fail("service rejected an explicit Plan tasks request")
      if (!root.service.forcePlanRequested) root.fail("explicit Plan tasks request did not force a fresh suggestion")
      root.phase = 2
      return
    }

    if (root.phase === 2) {
      var refreshed = root.service.calendarState.proposal
      if (root.service.solveState !== "ready" || !refreshed || Number(refreshed.baseInputRevision) !== root.service.calendarState.inputRevision) return
      if (root.service.forcePlanRequested) root.fail("explicit Plan tasks request remained pending after planning")
      if (!root.service.applyProposal()) root.fail("service rejected a ready proposal")
      if (root.service.calendarState.events.length !== 2) root.fail("Apply created planner events")
      root.phase = 3
      root.writeResult()
      poll.stop()
    }
  }

  Item { id: host }

  Timer {
    id: poll
    interval: 25
    repeat: true
    onTriggered: root.advance()
  }

  Component.onCompleted: Qt.callLater(root.start)
}
