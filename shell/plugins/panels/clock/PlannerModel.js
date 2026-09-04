// Pure planner presentation helpers. Keeping sorting, grouping, formatting,
// and explanation copy here lets the service remain the sole state owner and
// makes the model directly testable in Node.

var PRIORITY_ORDER = { high: 0, normal: 1, low: 2 }
var LOAD_ORDER = { high: 0, medium: 1, low: 2 }

function timestamp(value) {
  var parsed = Date.parse(value || "")
  return isFinite(parsed) ? parsed : Number.MAX_SAFE_INTEGER
}

function compareText(left, right) {
  return String(left || "").localeCompare(String(right || ""))
}

function compareTasks(left, right) {
  return (PRIORITY_ORDER[left.priority] === undefined ? 9 : PRIORITY_ORDER[left.priority]) -
    (PRIORITY_ORDER[right.priority] === undefined ? 9 : PRIORITY_ORDER[right.priority]) ||
    timestamp(left.deadlineAt) - timestamp(right.deadlineAt) ||
    (LOAD_ORDER[left.cognitiveLoad] === undefined ? 9 : LOAD_ORDER[left.cognitiveLoad]) -
      (LOAD_ORDER[right.cognitiveLoad] === undefined ? 9 : LOAD_ORDER[right.cognitiveLoad]) ||
    compareText(left.title, right.title) || compareText(left.id, right.id)
}

function compareEvents(left, right) {
  return timestamp(left.startAt) - timestamp(right.startAt) ||
    timestamp(left.endAt) - timestamp(right.endAt) ||
    compareText(left.title, right.title) || compareText(left.id, right.id)
}

function sortedTasks(tasks) {
  return (Array.isArray(tasks) ? tasks : []).slice().sort(compareTasks)
}

function sortedEvents(events) {
  return (Array.isArray(events) ? events : []).slice().sort(compareEvents)
}

function dayKey(value, timezone) {
  var parsed = new Date(value)
  if (isNaN(parsed.getTime())) return ""
  if (typeof Intl !== "undefined" && Intl.DateTimeFormat && timezone) {
    try {
      var parts = new Intl.DateTimeFormat("en-CA", {
        timeZone: timezone,
        year: "numeric",
        month: "2-digit",
        day: "2-digit"
      }).formatToParts(parsed)
      var fields = {}
      for (var i = 0; i < parts.length; i++) fields[parts[i].type] = parts[i].value
      return fields.year + "-" + fields.month + "-" + fields.day
    } catch (e) {}
  }
  return parsed.getFullYear() + "-" + String(parsed.getMonth() + 1).padStart(2, "0") + "-" + String(parsed.getDate()).padStart(2, "0")
}

function eventsByDay(events, timezone) {
  var result = {}
  var sorted = sortedEvents(events)
  for (var i = 0; i < sorted.length; i++) {
    var key = dayKey(sorted[i].startAt, timezone)
    if (!key) continue
    if (!result[key]) result[key] = []
    result[key].push(sorted[i])
  }
  return result
}

function eventsForDay(events, key, timezone) {
  return eventsByDay(events, timezone)[key] || []
}

function eventMarkers(events, timezone) {
  var grouped = eventsByDay(events, timezone)
  var result = {}
  for (var key in grouped) result[key] = grouped[key].length
  return result
}

function formatDuration(minutes) {
  var value = Math.max(0, Number(minutes) || 0)
  var hours = Math.floor(value / 60)
  var rest = value % 60
  if (hours && rest) return hours + "h " + rest + "m"
  if (hours) return hours + "h"
  return rest + "m"
}

function formatDeadline(value, timezone) {
  if (!value) return "No deadline"
  var parsed = new Date(value)
  if (isNaN(parsed.getTime())) return "Invalid deadline"
  var options = { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" }
  if (timezone) options.timeZone = timezone
  try { return new Intl.DateTimeFormat("en", options).format(parsed) } catch (e) { return parsed.toLocaleString() }
}

function priorityLabel(priority) {
  var value = String(priority || "normal")
  return value.charAt(0).toUpperCase() + value.slice(1)
}

function loadLabel(load) {
  var value = String(load || "medium")
  return value.charAt(0).toUpperCase() + value.slice(1)
}

function taskSummary(task, timezone) {
  return {
    id: task.id,
    title: task.title,
    duration: formatDuration(task.durationMinutes),
    deadline: formatDeadline(task.deadlineAt, timezone),
    priority: priorityLabel(task.priority),
    cognitiveLoad: loadLabel(task.cognitiveLoad),
    state: task.state
  }
}

function outcomeLabel(item) {
  var outcome = item && item.diagnostics ? item.diagnostics.outcome : ""
  if (outcome === "scheduled") return "Scheduled"
  if (outcome === "no_hard_feasible_slot") return "No feasible slot"
  if (outcome === "feasible_but_not_selected") return "Not selected"
  return "Needs review"
}

function explanation(item) {
  if (!item) return "No scheduling explanation available."
  if (item.explanation) return String(item.explanation)
  if (item.diagnostics && item.diagnostics.outcome === "no_hard_feasible_slot")
    return "No slot satisfies the hard timing or busy-time constraints."
  if (item.diagnostics && item.diagnostics.outcome === "feasible_but_not_selected")
    return "A feasible slot exists, but another task was selected first."
  return item.scheduled ? "Scheduled within the configured availability." : "Needs review."
}

function proposalItemForTask(proposal, taskId) {
  var items = proposal && Array.isArray(proposal.items) ? proposal.items : []
  for (var i = 0; i < items.length; i++) if (items[i] && items[i].taskId === taskId) return items[i]
  return null
}

function scheduledItems(proposal) {
  var items = proposal && Array.isArray(proposal.items) ? proposal.items : []
  return items.filter(function(item) { return item && item.scheduled === true }).slice().sort(function(a, b) {
    return timestamp(a.startAt) - timestamp(b.startAt) || compareText(a.taskId, b.taskId)
  })
}

function unscheduledItems(proposal) {
  var items = proposal && Array.isArray(proposal.items) ? proposal.items : []
  return items.filter(function(item) { return !item || item.scheduled !== true }).slice().sort(function(a, b) {
    return compareText(a && a.taskId, b && b.taskId)
  })
}

function proposalSummary(proposal) {
  var items = proposal && Array.isArray(proposal.items) ? proposal.items : []
  var scheduled = items.filter(function(item) { return item && item.scheduled }).length
  return { scheduled: scheduled, total: items.length, unscheduled: items.length - scheduled }
}

function penaltySummary(item) {
  return {
    cognitive: Number(item && item.cognitivePenalty || 0),
    fatigue: Number(item && item.fatiguePenalty || 0)
  }
}

function solveStateLabel(state) {
  var labels = {
    configuration_needed: "Configuration needed",
    idle: "Idle",
    queued: "Queued",
    solving: "Solving",
    ready: "Ready to review",
    error: "Planner error"
  }
  return labels[String(state || "")] || "Planner"
}

function applicabilityReasons(proposal, inputRevision) {
  var reasons = []
  function add(reason) {
    if (reason && reasons.indexOf(reason) === -1) reasons.push(reason)
  }
  var stored = proposal && Array.isArray(proposal.applicabilityReasons)
    ? proposal.applicabilityReasons
    : []
  for (var i = 0; i < stored.length; i++) add(stored[i])
  if (!proposal) return reasons
  if (proposal.status === "stale")
    add(proposal.staleReason === "inputs_changed"
      ? "Planning inputs changed; generate a new proposal before applying."
      : "This proposal is stale and cannot be applied.")
  if (inputRevision !== undefined && Number(proposal.baseInputRevision) !== Number(inputRevision))
    add("Planning inputs changed since this proposal was generated.")
  return reasons
}

if (typeof module !== "undefined") {
  module.exports = {
    PRIORITY_ORDER: PRIORITY_ORDER,
    sortedTasks: sortedTasks,
    sortedEvents: sortedEvents,
    dayKey: dayKey,
    eventsByDay: eventsByDay,
    eventsForDay: eventsForDay,
    eventMarkers: eventMarkers,
    formatDuration: formatDuration,
    formatDeadline: formatDeadline,
    priorityLabel: priorityLabel,
    loadLabel: loadLabel,
    taskSummary: taskSummary,
    outcomeLabel: outcomeLabel,
    explanation: explanation,
    proposalItemForTask: proposalItemForTask,
    scheduledItems: scheduledItems,
    unscheduledItems: unscheduledItems,
    proposalSummary: proposalSummary,
    penaltySummary: penaltySummary,
    solveStateLabel: solveStateLabel,
    applicabilityReasons: applicabilityReasons
  }
}
