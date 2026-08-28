// Pure parsing and scaling math for the agents panel's activity punchcard —
// the 7×24 weekday-hour dot grid a record renders when it carries
// `usageByHour`. Everything here is locale-, Qt- and clock-free (the
// collector has already bucketed usage into local-time hours), so the
// whole grid is unit-testable under node.

// The approved preview drew on a 24px cell pitch: dots 7px wide at the
// quietest lit cell growing to 20px at the busiest, empty cells carrying a
// 3px track dot. Those pixels live on as fractions of the pitch so the
// panel can pick whatever pitch fits its width — the proportions, and
// therefore the read, stay identical at any size.
var PITCH_REFERENCE = 24

var MIN_DOT = 7
var MAX_DOT = 20
var VOID_DOT = 3

var MIN_SIZE01 = MIN_DOT / PITCH_REFERENCE
var MAX_SIZE01 = MAX_DOT / PITCH_REFERENCE
var VOID_SIZE01 = VOID_DOT / PITCH_REFERENCE

var MIN_ALPHA = 0.35
var MAX_ALPHA = 1.0

var WEEKDAY_COUNT = 7
var HOUR_COUNT = 24

// ---- the record field ------------------------------------------------------

// A record's `usageByHour`: [{weekday, hour, tokens}, …] ordered by
// (weekday, hour) — all-time token counts bucketed into local-time
// weekday-hour cells, hours with no usage simply absent. Records are
// tool-written, not trusted: entries whose weekday (0–6, Sunday first) or
// hour (0–23) is missing, fractional, or out of range drop out, and so do
// entries without a positive finite token count — an empty cell is
// expressed by leaving it out, never by a zero. A duplicate (weekday,
// hour) keeps its last value, so a collector that rewrote a cell still
// renders the same grid. Anything that leaves no usable entries returns
// null, which is the panel's signal to hide the section entirely.
function parseUsageByHour(raw) {
  if (!Array.isArray(raw) || raw.length === 0) return null
  var byCell = {}
  var count = 0
  for (var i = 0; i < raw.length; i++) {
    var entry = raw[i] || {}
    var weekday = Number(entry.weekday)
    var hour = Number(entry.hour)
    var tokens = Number(entry.tokens)
    if (Math.floor(weekday) !== weekday || weekday < 0 || weekday >= WEEKDAY_COUNT) continue
    if (Math.floor(hour) !== hour || hour < 0 || hour >= HOUR_COUNT) continue
    if (!isFinite(tokens) || tokens <= 0) continue
    var key = weekday * HOUR_COUNT + hour
    if (byCell[key] === undefined) count++
    byCell[key] = { weekday: weekday, hour: hour, tokens: Math.round(tokens) }
  }
  if (count === 0) return null
  var keys = Object.keys(byCell).map(Number).sort(function(a, b) { return a - b })
  var out = []
  for (var k = 0; k < keys.length; k++) out.push(byCell[keys[k]])
  return out
}

// ---- dot scaling -----------------------------------------------------------
//
// A lit dot's diameter and ink both ride the square root of the cell's
// share of the window's busiest cell. Token counts carry a heavy tail —
// the K/M/B magnitudes formatTokenCount speaks in — and a linear ramp
// would crush almost every cell into the smallest dot while one furnace
// hour soaks up the whole scale. Square root spreads the quiet hours
// across the ramp and still leaves the peak visibly the peak. Both values
// are pure fractions: the panel multiplies by its own cell pitch and
// paints foreground at `alpha` over the section background.
function dotMetrics(tokens, maxTokens) {
  var value = Number(tokens) || 0
  var top = Number(maxTokens) || 0
  if (value <= 0 || top <= 0) return { size01: 0, alpha: 0 }
  var root = Math.sqrt(Math.min(1, value / top))
  return {
    size01: (MIN_DOT + (MAX_DOT - MIN_DOT) * root) / PITCH_REFERENCE,
    alpha: MIN_ALPHA + (MAX_ALPHA - MIN_ALPHA) * root
  }
}

// ---- the grid ---------------------------------------------------------------

// The rendered punchcard: `rows` is one array per weekday (Sunday first,
// matching the record's numbering) of 24 slots — a lit cell is
// {weekday, hour, tokens, size01, alpha} with its dot metrics already
// resolved against `maxTokens`, an empty slot null (the panel's faint
// track dot). null rather than an empty shell whenever nothing renders.
function punchcardWindow(raw) {
  var entries = parseUsageByHour(raw)
  if (!entries) return null

  var maxTokens = 0
  for (var i = 0; i < entries.length; i++)
    if (entries[i].tokens > maxTokens) maxTokens = entries[i].tokens

  var rows = []
  for (var weekday = 0; weekday < WEEKDAY_COUNT; weekday++) {
    var row = []
    for (var hour = 0; hour < HOUR_COUNT; hour++) row.push(null)
    rows.push(row)
  }

  for (var e = 0; e < entries.length; e++) {
    var entry = entries[e]
    var metrics = dotMetrics(entry.tokens, maxTokens)
    rows[entry.weekday][entry.hour] = {
      weekday: entry.weekday,
      hour: entry.hour,
      tokens: entry.tokens,
      size01: metrics.size01,
      alpha: metrics.alpha
    }
  }

  return { rows: rows, maxTokens: maxTokens }
}

if (typeof module !== "undefined") {
  module.exports = {
    PITCH_REFERENCE: PITCH_REFERENCE,
    MIN_SIZE01: MIN_SIZE01,
    MAX_SIZE01: MAX_SIZE01,
    VOID_SIZE01: VOID_SIZE01,
    MIN_ALPHA: MIN_ALPHA,
    MAX_ALPHA: MAX_ALPHA,
    parseUsageByHour: parseUsageByHour,
    dotMetrics: dotMetrics,
    punchcardWindow: punchcardWindow
  }
}
