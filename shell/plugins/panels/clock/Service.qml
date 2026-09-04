import QtQuick
import Quickshell
import Quickshell.Io
import "State.js" as State

// The calendar service is the only owner of planner state. Panels call the
// immutable State.js reducers through this object. Planning is local and
// one-shot; this service sends a bounded JSON request to the packaged solver
// and never starts a daemon or accesses the network.
Item {
  id: root

  property var shell: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var manifest: null

  property var calendarState: State.baseState()
  property bool stateLoaded: false
  property bool stateDirectoryReady: false
  property bool _hydrating: false
  property string lastInputFingerprint: ""
  property string lastPersistedJson: ""

  property string solveState: "configuration_needed"
  property string lastSolverError: ""
  property string activeRequestId: ""
  property int activeRequestRevision: -1
  property bool forcePlanRequested: false
  property string pendingPersistJson: ""
  property string lastPlanningDay: ""
  readonly property string solverPath: {
    var override = Quickshell.env("OMARCHY_CALENDAR_SOLVER")
    return override && String(override).trim() !== ""
      ? String(override)
      : "omarchy-calendar-solver"
  }
  property string pendingSolveJson: ""
  property string solverStdoutText: ""
  property string solverStderrText: ""
  property bool solveAgain: false
  property bool expectedSolverStop: false

  readonly property string stateHome: {
    var configured = Quickshell.env("XDG_STATE_HOME")
    return configured && configured !== ""
      ? configured
      : (Quickshell.env("HOME") || "") + "/.local/state"
  }
  readonly property string statePath: stateHome + "/omarchy/calendar.json"
  readonly property bool configured: State.settingsReady(calendarState.settings).ok
  readonly property bool hasInboxTasks: State.allTasksInInbox(calendarState)
  readonly property bool solving: debounceTimer.running || solverProcess.running
  readonly property string setupMessage: configured
    ? "Add a task to generate a suggested schedule."
    : "Choose a timezone and at least one availability window to enable planning."

  function parseState(raw) {
    if (!raw || String(raw).trim() === "") return State.baseState()
    try { return State.normalizeState(JSON.parse(String(raw))) }
    catch (error) {
      console.warn("calendar: state parse failed:", error)
      return State.baseState()
    }
  }

  function loadState(raw) {
    var next = parseState(raw)
    var reconciled = State.reconcileLinkedEvents(next, true)
    next = reconciled.state
    var fingerprint = State.problemFingerprint(next)
    var previousFingerprint = root.lastInputFingerprint
    root._hydrating = true
    root.calendarState = next
    root.lastInputFingerprint = fingerprint
    root.stateLoaded = true
    root._hydrating = false

    if (root.stateDirectoryReady && (reconciled.changed || String(raw || "").trim() === "")) root.persistState()
    if (previousFingerprint !== "" && previousFingerprint !== fingerprint) root.scheduleSolve()
    else if (previousFingerprint === "" && root.shouldSolve()) root.scheduleSolve()
  }

  function persistState() {
    if (!root.stateLoaded) return
    var json = JSON.stringify(root.calendarState, null, 2) + "\n"
    root.lastPersistedJson = json
    root.lastInputFingerprint = State.problemFingerprint(root.calendarState)
    root.pendingPersistJson = json
    persistTimer.restart()
  }

  function shouldSolve() {
    if (!root.stateLoaded || !root.configured || !root.hasInboxTasks) return false
    var proposal = root.calendarState.proposal
    return root.forcePlanRequested
      || !proposal
      || proposal.status !== "ready"
      || Number(proposal.baseInputRevision) !== root.calendarState.inputRevision
  }

  function planNow() {
    if (!root.stateLoaded) {
      root.lastSolverError = "The calendar service is still loading."
      return false
    }
    if (!root.configured) {
      root.lastSolverError = "Open Settings and choose a timezone and weekly availability before planning."
      root.solveState = "configuration_needed"
      return false
    }
    if (!root.hasInboxTasks) {
      root.lastSolverError = "Add a planning task before choosing Plan tasks."
      root.solveState = "idle"
      return false
    }
    root.forcePlanRequested = true
    root.lastSolverError = ""
    root.scheduleSolve()
    return true
  }

  function scheduleSolve() {
    if (!root.stateLoaded) return
    if (!root.configured || !root.hasInboxTasks) {
      root.solveState = root.configured ? "idle" : "configuration_needed"
      root.lastSolverError = ""
      return
    }
    root.solveState = "queued"
    debounceTimer.restart()
  }

  function startSolve() {
    if (solverProcess.running) {
      root.solveAgain = true
      root.expectedSolverStop = true
      solverProcess.running = false
      return
    }
    if (!root.shouldSolve()) {
      root.solveState = root.configured ? "idle" : "configuration_needed"
      return
    }
    var requestId = State.newId("solve", Date.now())
    root.activeRequestId = requestId
    root.activeRequestRevision = root.calendarState.inputRevision
    var request = {
      protocolVersion: 1,
      requestId: requestId,
      baseInputRevision: root.calendarState.inputRevision,
      now: new Date().toISOString(),
      settings: root.calendarState.settings,
      events: root.calendarState.events,
      tasks: root.calendarState.tasks,
      dependencies: root.calendarState.dependencies
    }
    root.lastSolverError = ""
    root.solveState = "solving"
    root.pendingSolveJson = JSON.stringify(request)
    root.solverStdoutText = ""
    root.solverStderrText = ""
    root.expectedSolverStop = false
    solverProcess.command = [root.solverPath]
    solverProcess.running = true
  }

  function commit(next) {
    if (next === root.calendarState) return next
    root.calendarState = next
    root.persistState()
    root.scheduleSolve()
    return next
  }

  function tutorialDismissed(key) {
    return State.tutorialDismissed(root.calendarState, key)
  }

  function dismissTutorial(key) {
    try {
      var next = State.dismissTutorial(root.calendarState, key)
      root.calendarState = next
      root.persistState()
      return true
    } catch (error) {
      root.lastSolverError = error.message
      return false
    }
  }

  function addEvent(input) {
    try { return root.commit(State.addEvent(root.calendarState, input, new Date())) }
    catch (error) { root.lastSolverError = error.message; return null }
  }

  function updateEvent(id, patch) {
    try { return root.commit(State.updateEvent(root.calendarState, id, patch, new Date())) }
    catch (error) { root.lastSolverError = error.message; return null }
  }

  function deleteEvent(id) {
    try { return root.commit(State.deleteEvent(root.calendarState, id)) }
    catch (error) { root.lastSolverError = error.message; return null }
  }

  function addTask(input) {
    try { return root.commit(State.addTask(root.calendarState, input, new Date())) }
    catch (error) { root.lastSolverError = error.message; return null }
  }

  function updateTask(id, patch) {
    try { return root.commit(State.updateTask(root.calendarState, id, patch, new Date())) }
    catch (error) { root.lastSolverError = error.message; return null }
  }

  function deleteTask(id) {
    try { return root.commit(State.deleteTask(root.calendarState, id)) }
    catch (error) { root.lastSolverError = error.message; return null }
  }

  function updateSettings(patch) {
    try { return root.commit(State.updateSettings(root.calendarState, patch, new Date())) }
    catch (error) { root.lastSolverError = error.message; return null }
  }

  function addDependency(fromTaskId, toTaskId) {
    try { return root.commit(State.addDependency(root.calendarState, fromTaskId, toTaskId)) }
    catch (error) { root.lastSolverError = error.message; return null }
  }

  function deleteDependency(fromTaskId, toTaskId) {
    try { return root.commit(State.deleteDependency(root.calendarState, fromTaskId, toTaskId)) }
    catch (error) { root.lastSolverError = error.message; return null }
  }

  function replaceTaskDependencies(taskId, predecessorIds) {
    try { return root.commit(State.replaceTaskDependencies(root.calendarState, taskId, predecessorIds)) }
    catch (error) { root.lastSolverError = error.message; return null }
  }

  function applyProposal() {
    try {
      var next = State.applyProposal(root.calendarState, new Date())
      return root.commit(next)
    } catch (error) { root.lastSolverError = error.message; return null }
  }

  function returnToInbox(taskId) {
    try { return root.commit(State.returnToInbox(root.calendarState, taskId, new Date())) }
    catch (error) { root.lastSolverError = error.message; return null }
  }

  // The CLI is a client of this service rather than a second state owner. It
  // sends JSON strings through IPC so the exact same reducers, revision rules,
  // stale-proposal checks, and atomic persistence serve both interfaces.
  function ipcState() {
    return {
      state: root.calendarState,
      loaded: root.stateLoaded,
      configured: root.configured,
      solveState: root.solveState,
      error: root.lastSolverError,
      errorOutput: ""
    }
  }

  function ipcResponse(next) {
    if (!next) return JSON.stringify({ ok: false, error: root.lastSolverError || "calendar operation failed" })
    return JSON.stringify({ ok: true, state: root.calendarState })
  }

  function ipcJson(raw, expectArray) {
    var value
    try { value = JSON.parse(String(raw || "")) }
    catch (error) { root.lastSolverError = "The calendar command received invalid JSON."; return null }
    if (expectArray ? !Array.isArray(value) : !value || typeof value !== "object" || Array.isArray(value)) {
      root.lastSolverError = "The calendar command received the wrong JSON value type."
      return null
    }
    return value
  }

  IpcHandler {
    target: "omarchy.calendar"

    function status(): string { return JSON.stringify(root.ipcState()) }
    function state(): string { return JSON.stringify({ ok: true, state: root.calendarState }) }

    function addEvent(inputJson: string): string {
      var input = root.ipcJson(inputJson, false)
      return input ? root.ipcResponse(root.addEvent(input)) : root.ipcResponse(null)
    }

    function updateEvent(id: string, patchJson: string): string {
      var patch = root.ipcJson(patchJson, false)
      return patch ? root.ipcResponse(root.updateEvent(id, patch)) : root.ipcResponse(null)
    }

    function deleteEvent(id: string): string { return root.ipcResponse(root.deleteEvent(id)) }

    function addTask(inputJson: string): string {
      var input = root.ipcJson(inputJson, false)
      return input ? root.ipcResponse(root.addTask(input)) : root.ipcResponse(null)
    }

    function updateTask(id: string, patchJson: string): string {
      var patch = root.ipcJson(patchJson, false)
      return patch ? root.ipcResponse(root.updateTask(id, patch)) : root.ipcResponse(null)
    }

    function deleteTask(id: string): string { return root.ipcResponse(root.deleteTask(id)) }

    function setSettings(patchJson: string): string {
      var patch = root.ipcJson(patchJson, false)
      return patch ? root.ipcResponse(root.updateSettings(patch)) : root.ipcResponse(null)
    }

    function addDependency(fromTaskId: string, toTaskId: string): string {
      return root.ipcResponse(root.addDependency(fromTaskId, toTaskId))
    }

    function deleteDependency(fromTaskId: string, toTaskId: string): string {
      return root.ipcResponse(root.deleteDependency(fromTaskId, toTaskId))
    }

    function setDependencies(taskId: string, predecessorJson: string): string {
      var predecessors = root.ipcJson(predecessorJson, true)
      return predecessors ? root.ipcResponse(root.replaceTaskDependencies(taskId, predecessors)) : root.ipcResponse(null)
    }

    function recompute(): string {
      return root.planNow() ? JSON.stringify(root.ipcState()) : root.ipcResponse(null)
    }

    function plan(): string {
      return root.planNow() ? JSON.stringify(root.ipcState()) : root.ipcResponse(null)
    }

    function apply(): string { return root.ipcResponse(root.applyProposal()) }
    function returnToInbox(taskId: string): string { return root.ipcResponse(root.returnToInbox(taskId)) }
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadState(text())
    onFileChanged: reload()
    onLoadFailed: root.loadState("")
  }

  Process {
    id: ensureStateDirectoryProcess
    command: ["mkdir", "-p", root.stateHome + "/omarchy"]
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.solveState = "error"
        root.lastSolverError = "The planner could not create its local state directory."
        return
      }
      root.stateDirectoryReady = true
      if (root.stateLoaded && root.lastPersistedJson === "") root.persistState()
      stateFile.reload()
    }
  }

  Timer {
    id: persistTimer
    interval: 100
    repeat: false
    onTriggered: {
      if (root.pendingPersistJson !== "") {
        stateFile.setText(root.pendingPersistJson)
        root.pendingPersistJson = ""
      }
    }
  }

  Timer {
    id: debounceTimer
    interval: 250
    repeat: false
    onTriggered: root.startSolve()
  }

  Process {
    id: solverProcess
    stdinEnabled: true

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (!root.expectedSolverStop) root.solverStdoutText = String(text || "")
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (!root.expectedSolverStop) root.solverStderrText = String(text || "")
    }

    onStarted: write(root.pendingSolveJson + "\n")

    onExited: function(exitCode) {
      var superseded = root.expectedSolverStop
      if (root.solveAgain) {
        root.solveAgain = false
        root.solveState = "queued"
        // Keep expectedSolverStop set until the replacement starts. Buffered
        // output from the canceled process must not become the new result.
        Qt.callLater(root.startSolve)
        return
      }

      if (superseded) return

      var requestId = root.activeRequestId
      var requestRevision = root.activeRequestRevision
      var stderr = String(root.solverStderrText || "").trim()
      if (stderr !== "") console.warn("calendar planner solver:", stderr)

      if (exitCode !== 0) {
        root.forcePlanRequested = false
        root.activeRequestId = ""
        root.solveState = "error"
        root.lastSolverError = "Omarchy could not generate a suggested schedule."
        return
      }

      var response
      try {
        response = JSON.parse(String(root.solverStdoutText || "").trim())
      } catch (error) {
        root.forcePlanRequested = false
        root.activeRequestId = ""
        root.solveState = "error"
        root.lastSolverError = "Omarchy could not read the planner result."
        console.warn("calendar planner: invalid solver response")
        return
      }

      if (!response || response.requestId !== requestId) {
        root.solveState = "queued"
        root.scheduleSolve()
        return
      }
      if (requestRevision !== root.calendarState.inputRevision) {
        root.solveState = "queued"
        root.scheduleSolve()
        return
      }
      if (!response.ok || !response.proposal) {
        root.forcePlanRequested = false
        root.activeRequestId = ""
        root.solveState = "error"
        root.lastSolverError = "Omarchy could not generate a suggested schedule."
        return
      }

      try {
        root.calendarState = State.writeProposal(root.calendarState, response.proposal)
        root.forcePlanRequested = false
        root.activeRequestId = ""
        root.solveState = "ready"
        root.persistState()
      } catch (error) {
        root.forcePlanRequested = false
        root.activeRequestId = ""
        root.solveState = "error"
        root.lastSolverError = "Omarchy could not save the planner result."
        console.warn("calendar planner:", error)
      }
    }
  }

  SystemClock {
    id: planningClock
    precision: SystemClock.Minutes
    onDateChanged: {
      var planningDay = Qt.formatDate(planningClock.date, "yyyy-MM-dd")
      if (root.lastPlanningDay === "") {
        root.lastPlanningDay = planningDay
      } else if (root.lastPlanningDay !== planningDay) {
        root.lastPlanningDay = planningDay
        root.scheduleSolve()
      }
    }
  }

  Component.onCompleted: {
    ensureStateDirectoryProcess.running = true
    root.lastPlanningDay = Qt.formatDate(new Date(), "yyyy-MM-dd")
    Qt.callLater(function() { stateFile.reload() })
  }
}
