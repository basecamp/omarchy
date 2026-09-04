import QtQuick
import Quickshell
import Quickshell.Io
import "State.js" as State
import "PlannerSolver.js" as PlannerSolver

// The calendar service is the only owner of planner state. Panels call the
// immutable State.js reducers through this object. Planning is pure and local;
// it never starts a daemon, reads the state file, or accesses the network.
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
  property string pendingPersistJson: ""
  property string lastPlanningDay: ""

  readonly property string stateHome: {
    var configured = Quickshell.env("XDG_STATE_HOME")
    return configured && configured !== ""
      ? configured
      : (Quickshell.env("HOME") || "") + "/.local/state"
  }
  readonly property string statePath: stateHome + "/omarchy/calendar.json"
  readonly property bool configured: State.settingsReady(calendarState.settings).ok
  readonly property bool hasInboxTasks: State.allTasksInInbox(calendarState)
  readonly property bool solving: debounceTimer.running
  readonly property string setupMessage: configured
    ? "Add a task to generate a schedule proposal."
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
    return !proposal || proposal.status !== "ready" || Number(proposal.baseInputRevision) !== root.calendarState.inputRevision
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
    try {
      var proposal = PlannerSolver.solve(request)
      if (root.activeRequestRevision !== root.calendarState.inputRevision) {
        root.solveState = "queued"
        debounceTimer.restart()
      } else {
        root.calendarState = State.writeProposal(root.calendarState, proposal)
        root.solveState = "ready"
        root.persistState()
      }
    } catch (error) {
      root.solveState = "error"
      root.lastSolverError = "The planner could not generate a proposal."
      console.warn("calendar planner:", error)
    }
    root.activeRequestId = ""
  }

  function commit(next) {
    if (next === root.calendarState) return next
    root.calendarState = next
    root.persistState()
    root.scheduleSolve()
    return next
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
      root.scheduleSolve()
      return JSON.stringify(root.ipcState())
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
