// Pure date-math + notes-persistence helpers for the calendar panel.
// No QML/Qt globals here on purpose (matches Weather's Model.js /
// Clipboard's ClipboardHistory.js convention) so this file stays testable
// in plain Node and locale-agnostic: callers pass in a `formatter`
// callback built from Qt.locale() when they want localized names,
// otherwise the English fallback below is used.

var MONTH_NAMES = ["January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December"]
var DAY_NAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
var DAY_SHORT = ["S", "M", "T", "W", "T", "F", "S"]

function pad2(n) { return (n < 10 ? "0" : "") + n }

function daysInMonth(year, month) {
  // month is 0-based; day 0 of the *next* month rolls back to the last
  // day of `month`.
  return new Date(year, month + 1, 0).getDate()
}

function isoDate(year, month, day) {
  return year + "-" + pad2(month + 1) + "-" + pad2(day)
}

function isoFromDate(date) {
  return isoDate(date.getFullYear(), date.getMonth(), date.getDate())
}

function isSameDate(a, b) {
  return !!a && !!b
    && a.getFullYear() === b.getFullYear()
    && a.getMonth() === b.getMonth()
    && a.getDate() === b.getDate()
}

function isSameMonth(a, b) {
  return !!a && !!b && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth()
}

// Normalizes JS's Sunday-first getDay() (0-6) to a week-start-aware index.
function weekdayIndex(date, weekStartsMonday) {
  var day = date.getDay() // 0=Sun..6=Sat
  return weekStartsMonday ? (day + 6) % 7 : day
}

function addMonths(year, month, delta) {
  var total = month + delta
  var y = year + Math.floor(total / 12)
  var m = ((total % 12) + 12) % 12
  return { year: y, month: m }
}

// Builds a fixed 6x7 grid (42 cells) so the panel height never jumps
// between months. Cells outside the target month are flagged `inMonth:
// false` but still carry a real Date so "prev/next month" click-throughs
// and the notes lookup both work uniformly.
function buildMonthGrid(year, month, weekStartsMonday, today) {
  var firstOfMonth = new Date(year, month, 1)
  var leadingBlanks = weekdayIndex(firstOfMonth, weekStartsMonday)
  var totalDays = daysInMonth(year, month)

  var cells = []
  for (var i = 0; i < 42; i++) {
    var dayOffset = i - leadingBlanks + 1
    var date = new Date(year, month, dayOffset)
    cells.push({
      date: date,
      iso: isoFromDate(date),
      day: date.getDate(),
      inMonth: dayOffset >= 1 && dayOffset <= totalDays,
      isToday: today ? isSameDate(date, today) : false,
      isWeekend: weekStartsMonday
        ? (date.getDay() === 0 || date.getDay() === 6)
        : (date.getDay() === 0 || date.getDay() === 6)
    })
  }
  return cells
}

function weekdayLabels(weekStartsMonday, formatter) {
  var order = []
  for (var i = 0; i < 7; i++) order.push(weekStartsMonday ? (i + 1) % 7 : i)
  return order.map(function(dayIndex) {
    if (formatter) return formatter(dayIndex)
    return DAY_SHORT[dayIndex]
  })
}

function monthTitle(year, month, formatter) {
  if (formatter) return formatter(year, month)
  return MONTH_NAMES[month] + " " + year
}

// Same algorithm as the bar Clock widget's isoWeek(), duplicated here
// rather than imported so this file stays a dependency-free module.
function isoWeek(date) {
  var d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()))
  var day = d.getUTCDay() || 7
  d.setUTCDate(d.getUTCDate() + 4 - day)
  var yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1))
  return Math.ceil(((d - yearStart) / 86400000 + 1) / 7)
}

function fullDayLabel(date, formatter) {
  if (!date) return ""
  if (formatter) return formatter(date)
  return DAY_NAMES[date.getDay()] + ", " + MONTH_NAMES[date.getMonth()] + " " + date.getDate()
}

// ---- Notes persistence -----------------------------------------------
// Stored as { "2026-07-19": ["text", "text"], ... } — flat map keeps the
// file trivially mergeable and the lookup O(1) per rendered cell.

function parseNotes(raw) {
  try {
    var parsed = JSON.parse(String(raw || "{}"))
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {}
    var clean = {}
    for (var key in parsed) {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(key)) continue
      var list = parsed[key]
      if (!Array.isArray(list)) continue
      var texts = list.map(function(v) { return String(v || "").trim() }).filter(function(v) { return v.length > 0 })
      if (texts.length > 0) clean[key] = texts
    }
    return clean
  } catch (e) {
    return {}
  }
}

function notesFor(notesMap, iso) {
  return (notesMap && Array.isArray(notesMap[iso])) ? notesMap[iso] : []
}

function addNote(notesMap, iso, text) {
  var trimmed = String(text || "").trim()
  var next = Object.assign({}, notesMap || {})
  if (!trimmed) return next
  var existing = Array.isArray(next[iso]) ? next[iso].slice() : []
  existing.push(trimmed)
  next[iso] = existing
  return next
}

function removeNote(notesMap, iso, index) {
  var next = Object.assign({}, notesMap || {})
  var existing = Array.isArray(next[iso]) ? next[iso].slice() : []
  if (index < 0 || index >= existing.length) return next
  existing.splice(index, 1)
  if (existing.length > 0) next[iso] = existing
  else delete next[iso]
  return next
}

function serializeNotes(notesMap) {
  return JSON.stringify(notesMap || {}, null, 2) + "\n"
}

if (typeof module !== "undefined") {
  module.exports = {
    daysInMonth: daysInMonth,
    isoDate: isoDate,
    isoFromDate: isoFromDate,
    isSameDate: isSameDate,
    isSameMonth: isSameMonth,
    weekdayIndex: weekdayIndex,
    isoWeek: isoWeek,
    addMonths: addMonths,
    buildMonthGrid: buildMonthGrid,
    weekdayLabels: weekdayLabels,
    monthTitle: monthTitle,
    fullDayLabel: fullDayLabel,
    parseNotes: parseNotes,
    notesFor: notesFor,
    addNote: addNote,
    removeNote: removeNote,
    serializeNotes: serializeNotes
  }
}
