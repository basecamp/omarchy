// Pure, deterministic planner used by the clock service.
//
// The service owns state, persistence, and IPC. This module only turns a
// request-shaped object into a proposal, which keeps the default installation
// self-contained and makes the scheduling rules directly testable.

var WEEKDAYS = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
var DAY_CODES = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
var RECURRENCE_LIMIT = 65535
var PRIORITY_ORDER = { high: 0, normal: 1, low: 2 }
var PRIORITY_SETTING = { low: "priorityLowWeight", normal: "priorityNormalWeight", high: "priorityHighWeight" }

function finite(value, fallback) {
  var result = Number(value)
  return isFinite(result) ? result : fallback
}

function timestamp(value) {
  var result = Date.parse(value || "")
  return isFinite(result) ? result : NaN
}

function dateParts(instant, timezone) {
  if (typeof Intl !== "undefined" && Intl.DateTimeFormat) {
    var parts = new Intl.DateTimeFormat("en-US", {
      timeZone: timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23"
    }).formatToParts(new Date(instant))
    var result = {}
    for (var i = 0; i < parts.length; i++) result[parts[i].type] = Number(parts[i].value)
    return result
  }

  // Qt's QML JavaScript engine does not expose Intl. Its Date accessors use
  // the desktop timezone, which is the timezone Omarchy configures for the
  // user. Node tests use the Intl branch above for non-system timezone cases.
  var local = new Date(instant)
  return {
    year: local.getFullYear(), month: local.getMonth() + 1, day: local.getDate(),
    hour: local.getHours(), minute: local.getMinutes(), second: local.getSeconds()
  }
}

function offsetMinutes(instant, timezone) {
  if (typeof Intl === "undefined" || !Intl.DateTimeFormat)
    return -new Date(instant).getTimezoneOffset()
  var local = dateParts(instant, timezone)
  var localAsUtc = Date.UTC(local.year, local.month - 1, local.day, local.hour, local.minute, local.second)
  return Math.round((localAsUtc - instant) / 60000)
}

function localToUtc(parts, timezone) {
  var wall = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour || 0, parts.minute || 0, parts.second || 0)
  var result = wall
  for (var i = 0; i < 4; i++) result = wall - offsetMinutes(result, timezone) * 60000
  return result
}

function addDays(parts, days) {
  var value = new Date(Date.UTC(parts.year, parts.month - 1, parts.day + days))
  return { year: value.getUTCFullYear(), month: value.getUTCMonth() + 1, day: value.getUTCDate() }
}

function addMonths(parts, months) {
  var value = new Date(Date.UTC(parts.year, parts.month - 1 + months, 1))
  var lastDay = new Date(Date.UTC(value.getUTCFullYear(), value.getUTCMonth() + 1, 0)).getUTCDate()
  return { year: value.getUTCFullYear(), month: value.getUTCMonth() + 1, day: Math.min(parts.day, lastDay) }
}

function weekday(date) {
  return WEEKDAYS[new Date(Date.UTC(date.year, date.month - 1, date.day)).getUTCDay()]
}

function clock(value) {
  var match = String(value || "").match(/^(\d{2}):(\d{2})$/)
  return match ? Number(match[1]) * 60 + Number(match[2]) : 0
}

function availableAt(instant, settings, timezone) {
  var local = dateParts(instant, timezone)
  var windows = settings.availability && settings.availability[weekday(local)] || []
  var minute = local.hour * 60 + local.minute
  for (var i = 0; i < windows.length; i++) {
    if (minute >= clock(windows[i].start) && minute < clock(windows[i].end)) return true
  }
  return false
}

function fitsAvailability(start, end, settings, timezone) {
  if (end <= start || !availableAt(start, settings, timezone)) return false
  // Availability windows cannot cross midnight. Checking the final occupied
  // minute is therefore enough and avoids walking every minute of every task.
  return availableAt(end - 60000, settings, timezone)
}

function recurrenceFields(rule) {
  var fields = {}
  var parts = String(rule || "").trim().replace(/^RRULE:/i, "").split(";")
  for (var i = 0; i < parts.length; i++) {
    var pair = parts[i].split("=")
    if (pair.length === 2) fields[pair[0].toUpperCase()] = pair[1].toUpperCase()
  }
  return fields
}

function recurrenceMatches(date, fields) {
  if (!fields.BYDAY) return true
  var days = fields.BYDAY.split(",")
  return days.indexOf(DAY_CODES[new Date(Date.UTC(date.year, date.month - 1, date.day)).getUTCDay()]) !== -1
}

function eventIntervals(event, horizonStart, horizonEnd) {
  var start = timestamp(event.startAt)
  var end = timestamp(event.endAt)
  if (!isFinite(start) || !isFinite(end) || end <= start) return []
  if (!event.rrule) return start < horizonEnd && end > horizonStart ? [{ id: event.id, start: start, end: end }] : []

  var fields = recurrenceFields(event.rrule)
  var frequency = fields.FREQ || ""
  if (["DAILY", "WEEKLY", "MONTHLY"].indexOf(frequency) === -1) throw new Error("unsupported event recurrence frequency")
  var timezone = event.timezone
  var initial = dateParts(start, timezone)
  var duration = end - start
  var interval = Math.max(1, finite(fields.INTERVAL, 1))
  var count = fields.COUNT ? Math.min(RECURRENCE_LIMIT, Math.max(0, finite(fields.COUNT, 0))) : RECURRENCE_LIMIT
  var until = fields.UNTIL ? timestamp(fields.UNTIL) : Infinity
  var result = []
  var seen = 0
  var day = { year: initial.year, month: initial.month, day: initial.day }
  var maxDays = frequency === "MONTHLY" ? 3660 : 3660

  for (var offset = 0; offset < maxDays && seen < count; offset++) {
    var matches = frequency === "DAILY"
      ? offset % interval === 0
      : frequency === "WEEKLY"
        ? Math.floor(offset / 7) % interval === 0 && recurrenceMatches(day, fields)
        : offset === 0 || (day.day === initial.day && Math.floor(offset / 28) % interval === 0)
    if (matches) {
      var occurrenceStart = localToUtc({
        year: day.year, month: day.month, day: day.day,
        hour: initial.hour, minute: initial.minute, second: initial.second
      }, timezone)
      if (occurrenceStart > until) break
      seen++
      var occurrenceEnd = occurrenceStart + duration
      if (occurrenceStart < horizonEnd && occurrenceEnd > horizonStart)
        result.push({ id: event.id, start: occurrenceStart, end: occurrenceEnd })
    }
    day = addDays(day, 1)
  }
  return result
}

function expandBusy(events, horizonStart, horizonEnd) {
  var result = []
  for (var i = 0; i < (events || []).length; i++) {
    var intervals = eventIntervals(events[i], horizonStart, horizonEnd)
    for (var j = 0; j < intervals.length; j++) result.push(intervals[j])
  }
  return result.sort(function(a, b) { return a.start - b.start || String(a.id).localeCompare(String(b.id)) })
}

function overlaps(start, end, interval) {
  return start < interval.end && interval.start < end
}

function priorityWeight(task, settings) {
  return finite(settings[PRIORITY_SETTING[task.priority] || PRIORITY_SETTING.normal], 0)
}

function cognitivePenalty(task, start, end, settings, timezone) {
  if (!settings.cognitiveEnabled) return 0
  var load = String(task.cognitiveLoad || "medium")
  var windowStart = clock(settings[load + "WindowStart"])
  var windowEnd = clock(settings[load + "WindowEnd"])
  var penalty = finite(settings[load + "OutsidePenalty"], 0)
  if (windowStart === windowEnd || penalty === 0) return 0
  var total = 0
  for (var cursor = start; cursor < end; cursor += 60000) {
    var minute = dateParts(cursor, timezone).hour * 60 + dateParts(cursor, timezone).minute
    if (minute < windowStart || minute >= windowEnd) total += penalty
  }
  return total
}

function predecessorsOf(dependencies) {
  var result = {}
  for (var i = 0; i < (dependencies || []).length; i++) {
    var dependency = dependencies[i]
    if (!result[dependency.toTaskId]) result[dependency.toTaskId] = []
    result[dependency.toTaskId].push(dependency.fromTaskId)
  }
  for (var key in result) result[key].sort()
  return result
}

function dependencyOrder(tasks, predecessors) {
  var sorted = tasks.slice().sort(function(a, b) {
    return (PRIORITY_ORDER[a.priority] === undefined ? 9 : PRIORITY_ORDER[a.priority]) -
      (PRIORITY_ORDER[b.priority] === undefined ? 9 : PRIORITY_ORDER[b.priority]) ||
      String(a.deadlineAt || "").localeCompare(String(b.deadlineAt || "")) || String(a.id).localeCompare(String(b.id))
  })
  var byId = {}
  for (var i = 0; i < sorted.length; i++) byId[sorted[i].id] = sorted[i]
  var visiting = {}, visited = {}, result = []
  function visit(task) {
    if (visited[task.id] || visiting[task.id]) return
    visiting[task.id] = true
    var parents = predecessors[task.id] || []
    for (var p = 0; p < parents.length; p++) if (byId[parents[p]]) visit(byId[parents[p]])
    delete visiting[task.id]
    visited[task.id] = true
    result.push(task)
  }
  for (var t = 0; t < sorted.length; t++) visit(sorted[t])
  return result
}

function recoveryPenalty(task, start, end, assignments, fixed, settings) {
  if (task.cognitiveLoad !== "high") return 0
  var recovery = finite(settings.recoveryMinutes, 0) * 60000
  var penalty = finite(settings.excessHighPenalty, 0)
  if (recovery <= 0 || penalty <= 0) return 0
  var total = 0
  function account(otherStart, otherEnd, high) {
    if (!high) return
    var gap = start >= otherStart ? start - otherEnd : otherStart - end
    if (gap >= 0 && gap < recovery) total += penalty
  }
  for (var i = 0; i < assignments.length; i++) account(assignments[i].start, assignments[i].end, assignments[i].high)
  for (var f = 0; f < fixed.length; f++) account(fixed[f].start, fixed[f].end, fixed[f].high)
  return total
}

function buildSlots(settings, start, end, now, timezone) {
  var slots = []
  var base = dateParts(start, timezone)
  var slotMinutes = Math.max(5, finite(settings.slotMinutes, 15))
  var horizonDays = Math.max(1, finite(settings.horizonDays, 14))
  for (var dayOffset = 0; dayOffset < horizonDays; dayOffset++) {
    var date = addDays(base, dayOffset)
    var windows = settings.availability && settings.availability[weekday(date)] || []
    if (!windows.length) continue
    for (var minute = 0; minute < 1440; minute += slotMinutes) {
      var slotStart = localToUtc({
        year: date.year, month: date.month, day: date.day,
        hour: Math.floor(minute / 60), minute: minute % 60
      }, timezone)
      var slotEnd = slotStart + slotMinutes * 60000
      if (slotStart >= now && slotEnd <= end && availableAt(slotStart, settings, timezone))
        slots.push({ start: slotStart, end: slotEnd })
    }
  }
  return slots
}

function proposalId(request) {
  var suffix = String(request.requestId || "local").replace(/[^a-zA-Z0-9]/g, "").slice(-12)
  return "proposal-" + Date.now() + "-" + suffix
}

function solve(request) {
  var settings = request.settings || {}
  var timezone = settings.timezone
  var now = timestamp(request.now)
  if (!timezone || !isFinite(now)) throw new Error("planner requires a timezone and timestamp")

  var localNow = dateParts(now, timezone)
  var horizonStart = localToUtc({ year: localNow.year, month: localNow.month, day: localNow.day }, timezone)
  var horizonDate = addDays(localNow, Math.max(1, finite(settings.horizonDays, 14)))
  var horizonEnd = localToUtc({ year: horizonDate.year, month: horizonDate.month, day: horizonDate.day }, timezone)
  var busy = expandBusy(request.events || [], horizonStart, horizonEnd)
  var slots = buildSlots(settings, horizonStart, horizonEnd, now, timezone)
  var predecessors = predecessorsOf(request.dependencies || [])
  var inbox = (request.tasks || []).filter(function(task) { return task.state === "inbox" })
  inbox.sort(function(a, b) {
    return priorityWeight(b, settings) - priorityWeight(a, settings) ||
      String(a.deadlineAt || "").localeCompare(String(b.deadlineAt || "")) || String(a.id).localeCompare(String(b.id))
  })

  var taskById = {}, fixed = []
  for (var ti = 0; ti < (request.tasks || []).length; ti++) taskById[request.tasks[ti].id] = request.tasks[ti]
  for (var ei = 0; ei < (request.events || []).length; ei++) {
    var event = request.events[ei]
    var linked = event.taskId && taskById[event.taskId]
    if (linked && linked.state === "applied") {
      var fixedStart = timestamp(event.startAt), fixedEnd = timestamp(event.endAt)
      if (isFinite(fixedStart) && isFinite(fixedEnd)) fixed.push({ start: fixedStart, end: fixedEnd, high: linked.cognitiveLoad === "high" })
    }
  }

  var candidates = {}, blockers = {}
  for (var i = 0; i < inbox.length; i++) {
    var task = inbox[i]
    var earliest = task.earliestAt ? timestamp(task.earliestAt) : -Infinity
    var deadline = task.deadlineAt ? timestamp(task.deadlineAt) : Infinity
    candidates[task.id] = []
    blockers[task.id] = []
    for (var s = 0; s < slots.length; s++) {
      var start = slots[s].start
      var end = start + finite(task.durationMinutes, 0) * 60000
      if (start < earliest || end > horizonEnd || !fitsAvailability(start, end, settings, timezone)) continue
      if (task.deadlineKind === "hard" && end > deadline) continue
      var blocked = false
      for (var b = 0; b < busy.length; b++) if (overlaps(start, end, busy[b])) {
        blocked = true
        if (blockers[task.id].indexOf(busy[b].id) === -1) blockers[task.id].push(busy[b].id)
      }
      if (!blocked) candidates[task.id].push({
        start: start,
        end: end,
        cognitive: cognitivePenalty(task, start, end, settings, timezone),
        softDeadline: task.deadlineKind === "soft" ? Math.max(0, Math.round((end - deadline) / 60000)) : 0
      })
    }
  }

  var assignments = [], assignedById = {}, ordered = dependencyOrder(inbox, predecessors)
  for (var oi = 0; oi < ordered.length; oi++) {
    var current = ordered[oi]
    var parents = predecessors[current.id] || [], ready = true, predecessorEnd = -Infinity
    for (var pi = 0; pi < parents.length; pi++) {
      if (!assignedById[parents[pi]]) { ready = false; break }
      predecessorEnd = Math.max(predecessorEnd, assignedById[parents[pi]].end)
    }
    if (!ready) continue
    var options = (candidates[current.id] || []).filter(function(candidate) {
      if (candidate.start < predecessorEnd) return false
      for (var a = 0; a < assignments.length; a++) if (overlaps(candidate.start, candidate.end, assignments[a])) return false
      return true
    })
    options.sort(function(a, b) {
      var aRecovery = recoveryPenalty(current, a.start, a.end, assignments, fixed, settings)
      var bRecovery = recoveryPenalty(current, b.start, b.end, assignments, fixed, settings)
      return (a.softDeadline + a.cognitive + aRecovery) - (b.softDeadline + b.cognitive + bRecovery) || a.start - b.start
    })
    if (options.length) {
      assignedById[current.id] = options[0]
      assignments.push({ id: current.id, start: options[0].start, end: options[0].end, high: current.cognitiveLoad === "high" })
    }
  }

  var items = [], medium = 0, soft = 0
  for (var ii = 0; ii < inbox.length; ii++) {
    var planned = inbox[ii], chosen = assignedById[planned.id]
    var feasible = (candidates[planned.id] || []).length > 0
    var cognitive = chosen ? cognitivePenalty(planned, chosen.start, chosen.end, settings, timezone) : 0
    var fatigue = chosen ? recoveryPenalty(planned, chosen.start, chosen.end, assignments, fixed, settings) : 0
    if (!chosen) medium -= priorityWeight(planned, settings)
    else {
      var late = planned.deadlineKind === "soft" && planned.deadlineAt
        ? Math.max(0, Math.round((chosen.end - timestamp(planned.deadlineAt)) / 60000)) : 0
      medium -= late
      soft -= cognitive + fatigue
    }
    items.push({
      taskId: planned.id,
      startAt: chosen ? new Date(chosen.start).toISOString() : null,
      endAt: chosen ? new Date(chosen.end).toISOString() : null,
      scheduled: !!chosen,
      cognitivePenalty: cognitive,
      fatiguePenalty: fatigue,
      explanation: chosen
        ? "Fits the configured availability without hard conflicts."
        : feasible
          ? "A feasible slot exists, but the proposal leaves this task unscheduled to protect higher-priority constraints."
          : "No slot satisfies the hard timing, availability, or busy-time constraints.",
      diagnostics: { outcome: chosen ? "scheduled" : feasible ? "feasible_but_not_selected" : "no_hard_feasible_slot" },
      busyBlockers: blockers[planned.id] || [],
      omittedBlockerCount: 0
    })
  }
  return {
    id: proposalId(request),
    status: "ready",
    baseInputRevision: Number(request.baseInputRevision) || 0,
    requestId: String(request.requestId || ""),
    horizonStart: new Date(horizonStart).toISOString(),
    horizonDays: Number(settings.horizonDays) || 14,
    timezone: timezone,
    score: { hard: 0, medium: medium, soft: soft },
    createdAt: new Date(now).toISOString(),
    items: items,
    applicabilityReasons: items.some(function(item) { return !item.scheduled })
      ? ["Some tasks remain in the inbox because no hard-feasible assignment was selected."]
      : []
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    solve: solve,
    expandBusy: expandBusy,
    fitsAvailability: fitsAvailability,
    localToUtc: localToUtc
  }
}
