// Native calendar state model.
//
// This module deliberately has no QML, filesystem, or process concerns. QML
// owns persistence and calls these immutable reducers; Node can load the same
// functions for fast state and migration tests.

var SCHEMA_VERSION = 1
var WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
var EVENT_ORIGINS = ["manual", "planner"]
var TASK_PRIORITIES = ["low", "normal", "high"]
var COGNITIVE_LOADS = ["low", "medium", "high"]
var DEADLINE_KINDS = ["none", "hard", "soft"]
var TASK_STATES = ["inbox", "applied", "missing_event"]
var PROPOSAL_STATUSES = ["ready", "stale", "applied"]

var DEFAULT_SETTINGS = {
  timezone: "",
  availability: {},
  horizonDays: 14,
  slotMinutes: 15,
  solveSeconds: 5,
  priorityLowWeight: 1,
  priorityNormalWeight: 5,
  priorityHighWeight: 25,
  cognitiveEnabled: false,
  lowWindowStart: "00:00",
  lowWindowEnd: "00:00",
  lowOutsidePenalty: 0,
  mediumWindowStart: "00:00",
  mediumWindowEnd: "00:00",
  mediumOutsidePenalty: 0,
  highWindowStart: "00:00",
  highWindowEnd: "00:00",
  highOutsidePenalty: 0,
  highStreakLimit: 1,
  recoveryMinutes: 30,
  excessHighPenalty: 60
}

var idCounter = 0

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function own(object, key) {
  return Object.prototype.hasOwnProperty.call(object, key)
}

function error(code, path, message) {
  var problem = new Error(message || code)
  problem.code = code
  problem.path = path || ""
  return problem
}

function fail(code, path, message) {
  throw error(code, path, message)
}

function nowIso(value) {
  var date
  if (value instanceof Date) date = value
  else if (typeof value === "number") date = new Date(value)
  else if (typeof value === "string" && value !== "") date = new Date(value)
  else date = new Date()
  if (isNaN(date.getTime())) date = new Date()
  return date.toISOString()
}

function newId(kind, now, randomValue) {
  idCounter += 1
  var millis = now === undefined || now === null ? Date.now() : Number(now)
  if (!isFinite(millis)) millis = Date.now()
  var random = randomValue === undefined || randomValue === null
    ? Math.random().toString(36).slice(2, 10)
    : String(randomValue).replace(/[^a-zA-Z0-9]/g, "").slice(0, 16)
  if (!random) random = "0"
  return String(kind) + "-" + Math.floor(millis) + "-" + idCounter + "-" + random
}

function validClock(value) {
  if (typeof value !== "string") return false
  var match = value.match(/^(\d{2}):(\d{2})$/)
  if (!match) return false
  return Number(match[1]) < 24 && Number(match[2]) < 60
}

function normalizeClock(value) {
  if (typeof value !== "string") return null
  var text = value.trim()
  var match = text.match(/^(\d{1,2}):(\d{1,2})$/)
  if (!match) return null
  var hours = Number(match[1])
  var minutes = Number(match[2])
  if (hours >= 24 || minutes >= 60) return null
  return (hours < 10 ? "0" : "") + hours + ":" + (minutes < 10 ? "0" : "") + minutes
}

function validTimezone(value) {
  if (typeof value !== "string" || value.trim() === "") return false
  if (value === "UTC" || value === "Etc/UTC") return true
  try {
    // Intl is available in Node and current QML JavaScript engines. The
    // fallback keeps the model useful in minimal test harnesses.
    if (typeof Intl !== "undefined" && Intl.DateTimeFormat) {
      Intl.DateTimeFormat("en-US", { timeZone: value }).format()
      return true
    }
  } catch (e) {
    return false
  }
  return /^[A-Za-z0-9._+-]+\/[A-Za-z0-9._+\/-]+$/.test(value)
}

function validTimestamp(value, path) {
  if (typeof value !== "string" || value.trim() === "")
    fail("invalid_timestamp", path, "timestamp must be an ISO-8601 string")
  var time = Date.parse(value)
  if (!isFinite(time)) fail("invalid_timestamp", path, "timestamp is not valid ISO-8601")
  return value
}

function validId(value, path) {
  if (typeof value !== "string" || value.trim() === "") fail("invalid_id", path, "id is required")
  return value
}

function defaultSettings() {
  return clone(DEFAULT_SETTINGS)
}

function normalizeAvailability(value) {
  var result = {}
  if (!isObject(value)) return result

  for (var i = 0; i < WEEKDAYS.length; i++) {
    var day = WEEKDAYS[i]
    if (!Array.isArray(value[day])) continue
    var windows = []
    for (var j = 0; j < value[day].length; j++) {
      var window = value[day][j]
      if (!isObject(window)) continue
      var start = normalizeClock(window.start)
      var end = normalizeClock(window.end)
      if (start !== null && end !== null && start < end)
        windows.push({ start: start, end: end })
    }
    if (windows.length > 0) {
      windows.sort(function(a, b) {
        return a.start.localeCompare(b.start) || a.end.localeCompare(b.end)
      })
      result[day] = windows
    }
  }
  return result
}

function normalizeSettings(value) {
  var input = isObject(value) ? value : {}
  var result = defaultSettings()
  for (var key in result) {
    if (own(input, key)) result[key] = clone(input[key])
  }
  result.timezone = typeof input.timezone === "string" ? input.timezone.trim() : ""
  result.availability = normalizeAvailability(input.availability)

  var integerKeys = [
    "horizonDays", "slotMinutes", "solveSeconds",
    "priorityLowWeight", "priorityNormalWeight", "priorityHighWeight",
    "lowOutsidePenalty", "mediumOutsidePenalty", "highOutsidePenalty",
    "highStreakLimit", "recoveryMinutes", "excessHighPenalty"
  ]
  for (var i = 0; i < integerKeys.length; i++) {
    var integerKey = integerKeys[i]
    var number = Number(result[integerKey])
    result[integerKey] = isFinite(number) ? Math.round(number) : DEFAULT_SETTINGS[integerKey]
  }
  result.cognitiveEnabled = !!result.cognitiveEnabled

  var clockKeys = [
    "lowWindowStart", "lowWindowEnd", "mediumWindowStart", "mediumWindowEnd",
    "highWindowStart", "highWindowEnd"
  ]
  for (var c = 0; c < clockKeys.length; c++) {
    var clockKey = clockKeys[c]
    var normalized = normalizeClock(result[clockKey])
    result[clockKey] = normalized === null ? DEFAULT_SETTINGS[clockKey] : normalized
  }
  return result
}

function configuredAvailability(settings) {
  var availability = settings && settings.availability
  if (!isObject(availability)) return 0
  var count = 0
  for (var i = 0; i < WEEKDAYS.length; i++) {
    var windows = availability[WEEKDAYS[i]]
    if (Array.isArray(windows)) count += windows.length
  }
  return count
}

function validateSettings(value, requireReady) {
  var settings = normalizeSettings(value)
  var problems = []
  var ranges = [
    ["horizonDays", 1, 90], ["slotMinutes", 5, 120], ["solveSeconds", 1, 120],
    ["priorityLowWeight", 0, Infinity], ["priorityNormalWeight", 0, Infinity],
    ["priorityHighWeight", 0, Infinity], ["lowOutsidePenalty", 0, Infinity],
    ["mediumOutsidePenalty", 0, Infinity], ["highOutsidePenalty", 0, Infinity],
    ["highStreakLimit", 1, Infinity], ["recoveryMinutes", 0, Infinity],
    ["excessHighPenalty", 0, Infinity]
  ]
  for (var i = 0; i < ranges.length; i++) {
    var range = ranges[i]
    if (!Number.isInteger(settings[range[0]]) || settings[range[0]] < range[1] || settings[range[0]] > range[2])
      problems.push({ code: "out_of_range", path: "settings." + range[0] })
  }

  var clockKeys = [
    "lowWindowStart", "lowWindowEnd", "mediumWindowStart", "mediumWindowEnd",
    "highWindowStart", "highWindowEnd"
  ]
  for (var c = 0; c < clockKeys.length; c++) {
    if (!validClock(settings[clockKeys[c]])) problems.push({ code: "invalid_clock", path: "settings." + clockKeys[c] })
  }
  var windowsByLoad = [
    ["lowWindowStart", "lowWindowEnd"],
    ["mediumWindowStart", "mediumWindowEnd"],
    ["highWindowStart", "highWindowEnd"]
  ]
  for (var w = 0; w < windowsByLoad.length; w++) {
    if (settings[windowsByLoad[w][1]] <= settings[windowsByLoad[w][0]] &&
        (settings[windowsByLoad[w][0]] !== "00:00" || settings[windowsByLoad[w][1]] !== "00:00"))
      problems.push({ code: "invalid_window", path: "settings." + windowsByLoad[w][0] })
  }

  if (settings.timezone !== "" && !validTimezone(settings.timezone))
    problems.push({ code: "invalid_timezone", path: "settings.timezone" })
  if (requireReady && settings.timezone === "")
    problems.push({ code: "timezone_required", path: "settings.timezone" })
  if (requireReady && configuredAvailability(settings) === 0)
    problems.push({ code: "availability_required", path: "settings.availability" })

  if (isObject(value) && isObject(value.availability)) {
    for (var day in value.availability) {
      if (WEEKDAYS.indexOf(day) === -1)
        problems.push({ code: "unknown_weekday", path: "settings.availability." + day })
      else if (!Array.isArray(value.availability[day]))
        problems.push({ code: "invalid_day_windows", path: "settings.availability." + day })
      else {
        for (var n = 0; n < value.availability[day].length; n++) {
          var rawWindow = value.availability[day][n]
          if (!isObject(rawWindow) || !validClock(rawWindow.start) || !validClock(rawWindow.end) || rawWindow.end <= rawWindow.start)
            problems.push({ code: "invalid_availability_window", path: "settings.availability." + day + "[" + n + "]" })
        }
      }
    }
  }
  return { ok: problems.length === 0, settings: settings, problems: problems }
}

function settingsReady(value) {
  return validateSettings(value, true)
}

function baseState() {
  return {
    schemaVersion: SCHEMA_VERSION,
    inputRevision: 0,
    settings: defaultSettings(),
    events: [],
    tasks: [],
    dependencies: [],
    proposal: null
  }
}

function normalizeEvent(value) {
  if (!isObject(value)) return null
  if (typeof value.id !== "string" || value.id === "") return null
  if (typeof value.title !== "string" || value.title.trim() === "") return null
  if (typeof value.startAt !== "string" || !isFinite(Date.parse(value.startAt))) return null
  if (typeof value.endAt !== "string" || !isFinite(Date.parse(value.endAt))) return null
  if (Date.parse(value.endAt) <= Date.parse(value.startAt)) return null
  if (!validTimezone(value.timezone)) return null
  if (EVENT_ORIGINS.indexOf(value.origin) === -1) return null
  var event = {
    id: value.id,
    title: value.title,
    description: typeof value.description === "string" ? value.description : "",
    startAt: value.startAt,
    endAt: value.endAt,
    timezone: value.timezone,
    allDay: !!value.allDay,
    rrule: typeof value.rrule === "string" && value.rrule !== "" ? value.rrule : null,
    origin: value.origin,
    taskId: typeof value.taskId === "string" ? value.taskId : null,
    proposalId: typeof value.proposalId === "string" ? value.proposalId : null,
    createdAt: typeof value.createdAt === "string" ? value.createdAt : nowIso(),
    updatedAt: typeof value.updatedAt === "string" ? value.updatedAt : nowIso()
  }
  return event
}

function normalizeTask(value) {
  if (!isObject(value)) return null
  if (typeof value.id !== "string" || value.id === "") return null
  if (typeof value.title !== "string" || value.title.trim() === "") return null
  var duration = Number(value.durationMinutes)
  if (!Number.isInteger(duration) || duration <= 0) return null
  if (TASK_PRIORITIES.indexOf(value.priority) === -1) return null
  if (COGNITIVE_LOADS.indexOf(value.cognitiveLoad) === -1) return null
  if (DEADLINE_KINDS.indexOf(value.deadlineKind) === -1) return null
  if (TASK_STATES.indexOf(value.state) === -1) return null
  if (value.earliestAt !== undefined && value.earliestAt !== null && !isFinite(Date.parse(value.earliestAt))) return null
  if (value.deadlineKind === "none" && value.deadlineAt !== undefined && value.deadlineAt !== null) return null
  if (value.deadlineKind !== "none" && (!value.deadlineAt || !isFinite(Date.parse(value.deadlineAt)))) return null
  return {
    id: value.id,
    title: value.title,
    durationMinutes: duration,
    priority: value.priority,
    cognitiveLoad: value.cognitiveLoad,
    earliestAt: value.earliestAt || null,
    deadlineKind: value.deadlineKind,
    deadlineAt: value.deadlineAt || null,
    state: value.state,
    linkedEventId: value.linkedEventId || null,
    createdAt: typeof value.createdAt === "string" ? value.createdAt : nowIso(),
    updatedAt: typeof value.updatedAt === "string" ? value.updatedAt : nowIso()
  }
}

function dependencyKey(dependency) {
  return dependency.fromTaskId + "\u0000" + dependency.toTaskId
}

function hasDependencyCycle(tasks, dependencies) {
  var outgoing = {}
  for (var i = 0; i < dependencies.length; i++) {
    var dependency = dependencies[i]
    if (!outgoing[dependency.fromTaskId]) outgoing[dependency.fromTaskId] = []
    outgoing[dependency.fromTaskId].push(dependency.toTaskId)
  }
  var visiting = {}
  var visited = {}
  function visit(id) {
    if (visiting[id]) return true
    if (visited[id]) return false
    visiting[id] = true
    var next = outgoing[id] || []
    for (var i = 0; i < next.length; i++) if (visit(next[i])) return true
    delete visiting[id]
    visited[id] = true
    return false
  }
  for (var t = 0; t < tasks.length; t++) if (visit(tasks[t].id)) return true
  return false
}

function normalizeProposal(value) {
  if (!isObject(value) || typeof value.id !== "string" || value.id === "") return null
  if (PROPOSAL_STATUSES.indexOf(value.status) === -1) return null
  var proposal = clone(value)
  proposal.applicabilityReasons = Array.isArray(proposal.applicabilityReasons) ? proposal.applicabilityReasons : []
  proposal.items = Array.isArray(proposal.items) ? proposal.items : []
  return proposal
}

function normalizeState(value) {
  var state = baseState()
  if (!isObject(value)) return state
  state.inputRevision = Number.isInteger(value.inputRevision) && value.inputRevision >= 0 ? value.inputRevision : 0
  state.settings = normalizeSettings(value.settings)

  var seenEvents = {}
  if (Array.isArray(value.events)) {
    for (var i = 0; i < value.events.length; i++) {
      var event = normalizeEvent(value.events[i])
      if (event && !seenEvents[event.id]) {
        seenEvents[event.id] = true
        state.events.push(event)
      }
    }
  }
  var seenTasks = {}
  if (Array.isArray(value.tasks)) {
    for (var t = 0; t < value.tasks.length; t++) {
      var task = normalizeTask(value.tasks[t])
      if (task && !seenTasks[task.id]) {
        seenTasks[task.id] = true
        state.tasks.push(task)
      }
    }
  }
  var seenDependencies = {}
  if (Array.isArray(value.dependencies)) {
    for (var d = 0; d < value.dependencies.length; d++) {
      var rawDependency = value.dependencies[d]
      if (!isObject(rawDependency)) continue
      var dependency = { fromTaskId: rawDependency.fromTaskId, toTaskId: rawDependency.toTaskId }
      var key = dependencyKey(dependency)
      if (typeof dependency.fromTaskId !== "string" || typeof dependency.toTaskId !== "string" ||
          dependency.fromTaskId === dependency.toTaskId || !seenTasks[dependency.fromTaskId] ||
          !seenTasks[dependency.toTaskId] || seenDependencies[key]) continue
      var candidate = state.dependencies.concat([dependency])
      if (hasDependencyCycle(state.tasks, candidate)) continue
      seenDependencies[key] = true
      state.dependencies.push(dependency)
    }
  }
  state.proposal = normalizeProposal(value.proposal)
  return state
}

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize)
  if (isObject(value)) {
    var result = {}
    var keys = Object.keys(value).sort()
    for (var i = 0; i < keys.length; i++) result[keys[i]] = canonicalize(value[keys[i]])
    return result
  }
  return value
}

function canonicalProblem(state) {
  var normalized = normalizeState(state)
  return canonicalize({
    settings: normalized.settings,
    events: normalized.events.slice().sort(function(a, b) { return a.id.localeCompare(b.id) }),
    tasks: normalized.tasks.slice().sort(function(a, b) { return a.id.localeCompare(b.id) }),
    dependencies: normalized.dependencies.slice().sort(function(a, b) {
      return dependencyKey(a).localeCompare(dependencyKey(b))
    })
  })
}

function canonicalJson(value) {
  return JSON.stringify(canonicalize(value))
}

function problemFingerprint(state) {
  var text = canonicalJson(canonicalProblem(state))
  // FNV-1a keeps the fingerprint compact without requiring Node-only crypto;
  // the canonical JSON is exported for diagnostics and collision-resistant
  // request construction can include it when needed.
  var hash = 2166136261
  for (var i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i)
    hash = Math.imul(hash, 16777619)
  }
  return (hash >>> 0).toString(16).padStart(8, "0")
}

function materialEventFields(event) {
  return {
    title: event.title,
    description: event.description || "",
    startAt: event.startAt,
    endAt: event.endAt,
    timezone: event.timezone,
    allDay: !!event.allDay,
    rrule: event.rrule || null
  }
}

function sameValue(a, b) {
  return canonicalJson(a) === canonicalJson(b)
}

function proposalForTask(state, taskId) {
  if (!state.proposal || !Array.isArray(state.proposal.items)) return null
  for (var i = 0; i < state.proposal.items.length; i++)
    if (state.proposal.items[i] && state.proposal.items[i].taskId === taskId) return state.proposal.items[i]
  return null
}

function staleProposal(proposal, reason) {
  if (!proposal || proposal.status === "applied") return proposal
  var result = clone(proposal)
  result.status = "stale"
  result.staleReason = reason || "inputs_changed"
  return result
}

function commitInput(state, next, reason) {
  next.inputRevision = state.inputRevision + 1
  next.proposal = staleProposal(next.proposal, reason)
  return next
}

function entityTimes(entity, now) {
  var stamp = nowIso(now)
  if (!entity.createdAt) entity.createdAt = stamp
  entity.updatedAt = stamp
  return entity
}

function eventFromInput(input, now) {
  var value = clone(input || {})
  if (!value.id) value.id = newId("event", Date.now())
  if (!value.origin) value.origin = "manual"
  if (!value.description) value.description = ""
  if (!value.rrule) value.rrule = null
  if (!value.taskId) value.taskId = null
  if (!value.proposalId) value.proposalId = null
  entityTimes(value, now)
  var event = normalizeEvent(value)
  if (!event) fail("invalid_event", "event", "event is invalid")
  return event
}

function taskFromInput(input, now) {
  var value = clone(input || {})
  if (!value.id) value.id = newId("task", Date.now())
  if (!value.priority) value.priority = "normal"
  if (!value.cognitiveLoad) value.cognitiveLoad = "medium"
  if (!value.deadlineKind) value.deadlineKind = "none"
  if (!value.state) value.state = "inbox"
  if (!value.linkedEventId) value.linkedEventId = null
  if (!value.earliestAt) value.earliestAt = null
  if (!value.deadlineAt) value.deadlineAt = null
  entityTimes(value, now)
  var task = normalizeTask(value)
  if (!task) fail("invalid_task", "task", "task is invalid")
  if (task.state !== "inbox") fail("invalid_task_state", "task.state", "new tasks must start in the inbox")
  return task
}

function addEvent(state, input, now) {
  var current = normalizeState(state)
  var event = eventFromInput(input, now)
  for (var i = 0; i < current.events.length; i++) if (current.events[i].id === event.id) fail("duplicate_id", "event.id")
  var next = clone(current)
  next.events.push(event)
  return commitInput(current, next, "event_changed")
}

function updateEvent(state, id, patch, now) {
  var current = normalizeState(state)
  var next = clone(current)
  var found = false
  for (var i = 0; i < next.events.length; i++) {
    if (next.events[i].id !== id) continue
    found = true
    var candidate = next.events[i]
    for (var key in patch || {}) if (key !== "id" && key !== "createdAt" && key !== "updatedAt") candidate[key] = clone(patch[key])
    candidate.updatedAt = nowIso(now)
    var normalized = normalizeEvent(candidate)
    if (!normalized) fail("invalid_event", "event")
    next.events[i] = normalized
    break
  }
  if (!found) fail("missing_event", "event.id")
  return reconcileLinkedEvents(commitInput(current, next, "event_changed"), false).state
}

function deleteEvent(state, id) {
  var current = normalizeState(state)
  var next = clone(current)
  var before = next.events.length
  next.events = next.events.filter(function(event) { return event.id !== id })
  if (next.events.length === before) fail("missing_event", "event.id")
  return reconcileLinkedEvents(commitInput(current, next, "event_changed"), false).state
}

function addTask(state, input, now) {
  var current = normalizeState(state)
  var task = taskFromInput(input, now)
  for (var i = 0; i < current.tasks.length; i++) if (current.tasks[i].id === task.id) fail("duplicate_id", "task.id")
  var next = clone(current)
  next.tasks.push(task)
  return commitInput(current, next, "task_changed")
}

function updateTask(state, id, patch, now) {
  var current = normalizeState(state)
  var next = clone(current)
  var found = false
  for (var i = 0; i < next.tasks.length; i++) {
    if (next.tasks[i].id !== id) continue
    found = true
    if (next.tasks[i].state === "applied" || next.tasks[i].state === "missing_event")
      fail("applied_task_locked", "task.state", "return the task to the inbox before editing it")
    var candidate = next.tasks[i]
    for (var key in patch || {}) if (key !== "id" && key !== "createdAt" && key !== "updatedAt" && key !== "state" && key !== "linkedEventId") candidate[key] = clone(patch[key])
    candidate.updatedAt = nowIso(now)
    var normalized = normalizeTask(candidate)
    if (!normalized) fail("invalid_task", "task")
    next.tasks[i] = normalized
    break
  }
  if (!found) fail("missing_task", "task.id")
  return commitInput(current, next, "task_changed")
}

function deleteTask(state, id) {
  var current = normalizeState(state)
  var task = null
  for (var i = 0; i < current.tasks.length; i++) if (current.tasks[i].id === id) task = current.tasks[i]
  if (!task) fail("missing_task", "task.id")
  if (task.state === "applied") fail("applied_task_locked", "task.state", "return the task to the inbox before deleting it")
  var next = clone(current)
  next.tasks = next.tasks.filter(function(candidate) { return candidate.id !== id })
  next.dependencies = next.dependencies.filter(function(dependency) {
    return dependency.fromTaskId !== id && dependency.toTaskId !== id
  })
  return commitInput(current, next, "task_changed")
}

function updateSettings(state, patch, now) {
  var current = normalizeState(state)
  var candidate = clone(current.settings)
  for (var key in patch || {}) candidate[key] = clone(patch[key])
  var validation = validateSettings(candidate, false)
  if (!validation.ok) fail(validation.problems[0].code, validation.problems[0].path, "settings are invalid")
  var next = clone(current)
  next.settings = validation.settings
  return commitInput(current, next, "settings_changed")
}

function addDependency(state, fromTaskId, toTaskId) {
  var current = normalizeState(state)
  if (fromTaskId === toTaskId) fail("self_dependency", "dependency")
  var taskIds = {}
  for (var i = 0; i < current.tasks.length; i++) taskIds[current.tasks[i].id] = true
  if (!taskIds[fromTaskId] || !taskIds[toTaskId]) fail("missing_task", "dependency")
  var dependency = { fromTaskId: fromTaskId, toTaskId: toTaskId }
  for (var d = 0; d < current.dependencies.length; d++)
    if (dependencyKey(current.dependencies[d]) === dependencyKey(dependency)) fail("duplicate_dependency", "dependency")
  var next = clone(current)
  next.dependencies.push(dependency)
  if (hasDependencyCycle(next.tasks, next.dependencies)) fail("dependency_cycle", "dependency")
  return commitInput(current, next, "dependency_changed")
}

function deleteDependency(state, fromTaskId, toTaskId) {
  var current = normalizeState(state)
  var key = dependencyKey({ fromTaskId: fromTaskId, toTaskId: toTaskId })
  var next = clone(current)
  next.dependencies = next.dependencies.filter(function(dependency) { return dependencyKey(dependency) !== key })
  if (next.dependencies.length === current.dependencies.length) fail("missing_dependency", "dependency")
  return commitInput(current, next, "dependency_changed")
}

function replaceTaskDependencies(state, taskId, predecessorIds) {
  var current = normalizeState(state)
  var taskIds = {}
  var found = false
  for (var i = 0; i < current.tasks.length; i++) {
    taskIds[current.tasks[i].id] = true
    if (current.tasks[i].id === taskId) found = true
  }
  if (!found) fail("missing_task", "task.id")
  var next = clone(current)
  next.dependencies = next.dependencies.filter(function(dependency) { return dependency.toTaskId !== taskId })
  var seen = {}
  var ids = Array.isArray(predecessorIds) ? predecessorIds : []
  for (var p = 0; p < ids.length; p++) {
    var predecessorId = String(ids[p])
    if (!taskIds[predecessorId]) fail("missing_task", "dependency.fromTaskId")
    if (predecessorId === taskId) fail("self_dependency", "dependency")
    if (seen[predecessorId]) continue
    seen[predecessorId] = true
    next.dependencies.push({ fromTaskId: predecessorId, toTaskId: taskId })
    if (hasDependencyCycle(next.tasks, next.dependencies)) fail("dependency_cycle", "dependency")
  }
  var currentKeys = current.dependencies.map(dependencyKey).sort()
  var nextKeys = next.dependencies.map(dependencyKey).sort()
  if (sameValue(currentKeys, nextKeys)) return current
  return commitInput(current, next, "dependency_changed")
}

function writeProposal(state, proposal) {
  var current = normalizeState(state)
  var nextProposal = normalizeProposal(proposal)
  if (!nextProposal) fail("invalid_proposal", "proposal")
  if (Number(nextProposal.baseInputRevision) !== current.inputRevision)
    fail("stale_proposal", "proposal.baseInputRevision")
  nextProposal.status = "ready"
  var next = clone(current)
  next.proposal = nextProposal
  // Proposal persistence is derived output and must not advance the input
  // revision or trigger another automatic solve.
  return next
}

function applyProposal(state, appliedAt) {
  var current = normalizeState(state)
  var proposal = current.proposal
  if (!proposal) fail("missing_proposal", "proposal")
  if (proposal.status !== "ready") fail("proposal_not_ready", "proposal.status")
  if (Number(proposal.baseInputRevision) !== current.inputRevision)
    fail("stale_proposal", "proposal.baseInputRevision")

  var next = clone(current)
  var stamp = nowIso(appliedAt)
  var taskById = {}
  for (var i = 0; i < next.tasks.length; i++) taskById[next.tasks[i].id] = next.tasks[i]
  var scheduled = {}
  var items = Array.isArray(proposal.items) ? proposal.items : []
  for (var p = 0; p < items.length; p++) {
    var item = items[p]
    if (!item || !item.scheduled) continue
    var task = taskById[item.taskId]
    if (!task) fail("missing_task", "proposal.items[" + p + "].taskId")
    if (task.state !== "inbox") fail("task_not_inbox", "proposal.items[" + p + "].taskId")
    if (!item.startAt || !item.endAt || !isFinite(Date.parse(item.startAt)) || !isFinite(Date.parse(item.endAt)) || Date.parse(item.endAt) <= Date.parse(item.startAt))
      fail("invalid_proposal_interval", "proposal.items[" + p + "]")
    if (!validTimezone(proposal.timezone || next.settings.timezone)) fail("invalid_timezone", "proposal.timezone")
    var event = {
      id: newId("event", Date.now()),
      title: task.title,
      description: "",
      startAt: item.startAt,
      endAt: item.endAt,
      timezone: proposal.timezone || next.settings.timezone,
      allDay: false,
      rrule: null,
      origin: "planner",
      taskId: task.id,
      proposalId: proposal.id,
      createdAt: stamp,
      updatedAt: stamp
    }
    next.events.push(event)
    task.state = "applied"
    task.linkedEventId = event.id
    task.updatedAt = stamp
    scheduled[task.id] = true
  }
  for (var t = 0; t < next.tasks.length; t++) {
    if (scheduled[next.tasks[t].id]) continue
    // Unscheduled tasks remain inbox tasks, including their explanations in
    // the proposal item rather than silently changing their state.
    if (next.tasks[t].state === "inbox") next.tasks[t].updatedAt = next.tasks[t].updatedAt
  }
  next.proposal.status = "applied"
  next.proposal.appliedAt = stamp
  return commitInput(current, next, "proposal_applied")
}

function returnToInbox(state, taskId, now) {
  var current = normalizeState(state)
  var next = clone(current)
  var task = null
  for (var i = 0; i < next.tasks.length; i++) if (next.tasks[i].id === taskId) task = next.tasks[i]
  if (!task) fail("missing_task", "task.id")
  if (task.state !== "applied" && task.state !== "missing_event") fail("task_not_applied", "task.state")
  var linkedId = task.linkedEventId
  if (linkedId) next.events = next.events.filter(function(event) { return event.id !== linkedId })
  task.state = "inbox"
  task.linkedEventId = null
  task.updatedAt = nowIso(now)
  return commitInput(current, next, "task_returned_to_inbox")
}

function reconcileLinkedEvents(state, advanceRevision) {
  var current = normalizeState(state)
  var next = clone(current)
  var changed = false
  for (var i = 0; i < next.tasks.length; i++) {
    var task = next.tasks[i]
    if (task.state !== "applied" || !task.linkedEventId) continue
    var event = null
    for (var e = 0; e < next.events.length; e++) if (next.events[e].id === task.linkedEventId) event = next.events[e]
    var item = proposalForTask(next, task.id)
    var material = event && item && item.startAt && item.endAt ? {
      title: task.title,
      description: "",
      startAt: item.startAt,
      endAt: item.endAt,
      timezone: next.proposal.timezone || next.settings.timezone,
      allDay: false,
      rrule: null
    } : null
    if (!event || (material && !sameValue(materialEventFields(event), material))) {
      task.state = "missing_event"
      task.updatedAt = nowIso()
      changed = true
    }
  }
  if (changed && advanceRevision) return { state: commitInput(current, next, "linked_event_changed"), changed: true }
  return { state: next, changed: changed }
}

function allTasksInInbox(state) {
  var current = normalizeState(state)
  for (var i = 0; i < current.tasks.length; i++) if (current.tasks[i].state === "inbox") return true
  return false
}

if (typeof module !== "undefined") {
  module.exports = {
    SCHEMA_VERSION: SCHEMA_VERSION,
    WEEKDAYS: WEEKDAYS.slice(),
    DEFAULT_SETTINGS: defaultSettings(),
    defaultSettings: defaultSettings,
    normalizeClock: normalizeClock,
    validClock: validClock,
    validTimezone: validTimezone,
    validateSettings: validateSettings,
    settingsReady: settingsReady,
    baseState: baseState,
    normalizeState: normalizeState,
    canonicalize: canonicalize,
    canonicalJson: canonicalJson,
    canonicalProblem: canonicalProblem,
    problemFingerprint: problemFingerprint,
    hasDependencyCycle: hasDependencyCycle,
    newId: newId,
    addEvent: addEvent,
    updateEvent: updateEvent,
    deleteEvent: deleteEvent,
    addTask: addTask,
    updateTask: updateTask,
    deleteTask: deleteTask,
    updateSettings: updateSettings,
    addDependency: addDependency,
    deleteDependency: deleteDependency,
    replaceTaskDependencies: replaceTaskDependencies,
    writeProposal: writeProposal,
    applyProposal: applyProposal,
    returnToInbox: returnToInbox,
    reconcileLinkedEvents: reconcileLinkedEvents,
    allTasksInInbox: allTasksInInbox,
    error: error
  }
}
