// Pure geometry and intensity math for the agents panel's usage heatmap —
// the GitHub-style calendar a record renders when it carries `usageByDay`.
// Everything here is locale-, Qt- and clock-free (the caller passes today
// in as a string), so the whole grid is unit-testable under node.

// The calendar never grows past this many week columns, no matter how far
// back the record reaches; older days scroll off the left.
var MAX_WEEKS = 16

var MONTH_LABELS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// ---- dates -----------------------------------------------------------------
//
// Calendar math runs on local midnights. Constructing Date(y, m-1, d) and
// rounding the millisecond division keeps day counts exact across DST jumps
// (a "day" is 23–25h there) in every timezone the shell runs in.

var MS_PER_DAY = 86400000

function dateParts(text) {
  var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(text || ""))
  if (!match) return null
  return { year: Number(match[1]), month: Number(match[2]), day: Number(match[3]) }
}

function dateToMs(text) {
  var parts = dateParts(text)
  if (!parts) return NaN
  return new Date(parts.year, parts.month - 1, parts.day).getTime()
}

function isValidDate(text) {
  var ms = dateToMs(text)
  if (!isFinite(ms)) return false
  // Reject well-formed strings that are not real dates ("2026-02-30"): the
  // calendar normalizes those to the next month, so the round trip moves.
  var parsed = new Date(ms)
  return parsed.getMonth() === dateParts(text).month - 1
    && parsed.getDate() === dateParts(text).day
}

function addDays(text, count) {
  var ms = dateToMs(text)
  if (!isFinite(ms)) return ""
  var shifted = new Date(ms + count * MS_PER_DAY)
  return shifted.getFullYear()
    + "-" + String(shifted.getMonth() + 1).padStart(2, "0")
    + "-" + String(shifted.getDate()).padStart(2, "0")
}

function daysBetween(fromText, toText) {
  var from = dateToMs(fromText)
  var to = dateToMs(toText)
  if (!isFinite(from) || !isFinite(to)) return 0
  return Math.round((to - from) / MS_PER_DAY)
}

// Monday-first row position, matching the grid's seven-row layout.
function weekdaySlot(text) {
  var ms = dateToMs(text)
  if (!isFinite(ms)) return 0
  return (new Date(ms).getDay() + 6) % 7
}

// ---- the record field ------------------------------------------------------

// A record's `usageByDay`: [{date, tokens}, …] ascending, quiet days
// included with zero tokens. Records are tool-written, not trusted: entries
// with unparseable dates drop out, token counts coerce to non-negative
// integers, and the array re-sorts — a collector that appended out of order
// or rewrote a day still renders the same grid (last value wins).
function parseUsageByDay(raw) {
  if (!Array.isArray(raw)) return []
  var byDate = {}
  for (var i = 0; i < raw.length; i++) {
    var entry = raw[i] || {}
    var date = String(entry.date || "")
    if (!isValidDate(date)) continue
    var tokens = Number(entry.tokens)
    if (!isFinite(tokens) || tokens < 0) tokens = 0
    byDate[date] = Math.round(tokens)
  }
  var dates = Object.keys(byDate).sort()
  var out = []
  for (var d = 0; d < dates.length; d++) out.push({ date: dates[d], tokens: byDate[dates[d]] })
  return out
}

// ---- intensity -------------------------------------------------------------
//
// Level 0 is a quiet day; levels 1–4 band the day's share of the window's
// busiest day in powers of four (≥1/64, ≥1/16, ≥1/4 of the max). Fixed
// max-relative bands rather than per-window quantiles: quantile thresholds
// shift whenever any day's count changes, repainting cells whose own usage
// did not move, while a banded share only repaints the days that actually
// crossed a boundary. Powers of four also spread the heavy tail token
// counts naturally carry (the K/M/B magnitudes formatTokenCount speaks in)
// across the whole ramp instead of piling most days into the lowest level.
function intensityLevel(tokens, maxTokens) {
  var value = Number(tokens) || 0
  var top = Number(maxTokens) || 0
  if (value <= 0 || top <= 0) return 0
  var share = value / top
  if (share >= 0.25) return 4
  if (share >= 0.0625) return 3
  if (share >= 0.015625) return 2
  return 1
}

// ---- the grid --------------------------------------------------------------

// The rendered calendar: `weeks` is one array per week column, each holding
// seven Monday-first slots ending at `todayDate`. A slot is
// {date, tokens, level} when the record covers that date and it is not in
// the future, and null otherwise — a day the record never mentions stays
// unpainted rather than counting as a quiet one, and days after today (a
// clock-skewed collector) render nothing. The window starts at the first
// covered date so a young record grows from the left; past maxWeeks the
// oldest whole weeks trim off. `monthLabels` aligns with the columns: a
// month is named in the column its first covered 1st falls in, so the
// usual clipped first column simply goes unnamed, and consecutive months
// can never collide (their firsts sit at least four columns apart).
function heatmapWindow(rawEntries, todayDate, maxWeeks) {
  var empty = { weeks: [], monthLabels: [] }
  var today = String(todayDate || "")
  if (!isValidDate(today)) return empty

  var entries = parseUsageByDay(rawEntries)
  if (entries.length === 0) return empty

  var lastCovered = entries[entries.length - 1].date
  var visibleEnd = lastCovered > today ? today : lastCovered
  var visibleStart = entries[0].date
  if (visibleEnd < visibleStart) return empty

  var weeks = Math.max(1, Number(maxWeeks) > 0 ? Math.floor(maxWeeks) : MAX_WEEKS)
  var lead = weekdaySlot(visibleStart)
  var columns = Math.ceil((lead + daysBetween(visibleStart, visibleEnd) + 1) / 7)
  if (columns > weeks) {
    visibleStart = addDays(visibleStart, (columns - weeks) * 7)
    columns = weeks
  }

  var byDate = {}
  var maxTokens = 0
  for (var e = 0; e < entries.length; e++) {
    var date = entries[e].date
    if (date < visibleStart) continue
    byDate[date] = entries[e].tokens
    if (date <= today && byDate[date] > maxTokens) maxTokens = byDate[date]
  }

  var grid = []
  for (var w = 0; w < columns; w++) {
    var column = []
    for (var slot = 0; slot < 7; slot++) {
      var cellDate = addDays(visibleStart, w * 7 + slot - lead)
      if (cellDate <= today && byDate[cellDate] !== undefined)
        column.push({ date: cellDate, tokens: byDate[cellDate], level: intensityLevel(byDate[cellDate], maxTokens) })
      else
        column.push(null)
    }
    grid.push(column)
  }

  var labels = []
  var lastMonth = -1
  for (var lw = 0; lw < grid.length; lw++) {
    var label = ""
    for (var ls = 0; ls < 7; ls++) {
      var cell = grid[lw][ls]
      if (cell && cell.date.slice(8) === "01") {
        var month = Number(cell.date.slice(5, 7)) - 1
        if (month !== lastMonth) {
          label = MONTH_LABELS[month]
          lastMonth = month
        }
        break
      }
    }
    labels.push(label)
  }

  return { weeks: grid, monthLabels: labels }
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_WEEKS: MAX_WEEKS,
    MONTH_LABELS: MONTH_LABELS,
    parseUsageByDay: parseUsageByDay,
    intensityLevel: intensityLevel,
    heatmapWindow: heatmapWindow
  }
}
