#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const Punchcard = requireFromRoot('shell/plugins/agents/PunchcardModel.js')

// ---- absent / malformed fields -> no section -------------------------------
assert(Punchcard.parseUsageByHour(null) === null, 'parseUsageByHour(null) -> null (section hidden)')
assert(Punchcard.parseUsageByHour(undefined) === null, 'parseUsageByHour(undefined) -> null')
assert(Punchcard.parseUsageByHour('x') === null, 'parseUsageByHour(non-array) -> null')
assert(Punchcard.parseUsageByHour(null) === null, 'parseUsageByHour(null) -> null')
assert(Punchcard.parseUsageByHour('x') === null, 'parseUsageByHour(non-array) -> null')

// ---- parse: bounds, coercion, dedupe ---------------------------------------
const bad = Punchcard.parseUsageByHour([
  { weekday: -1, hour: 5, tokens: 10 },
  { weekday: 7, hour: 5, tokens: 10 },
  { weekday: 1.5, hour: 5, tokens: 10 },
  { weekday: 1, hour: 24, tokens: 10 },
  { weekday: 1, hour: -1, tokens: 10 },
  { weekday: null, hour: 5, tokens: 10 },
  { weekday: 1, hour: null, tokens: 10 },
  { weekday: 1, hour: 5, tokens: null },
  { weekday: 1, hour: 5, tokens: -3 },
])
assert(bad === null, 'every out-of-bounds / null / negative entry dropped -> null')

const dupe = Punchcard.parseUsageByHour([
  { weekday: 1, hour: 5, tokens: 10 },
  { weekday: 1, hour: 5, tokens: 20 },
])
assert(dupe.length === 1 && dupe[0].tokens === 20, 'duplicate (weekday, hour) keeps its last value')

// ---- grid geometry ---------------------------------------------------------
const mkDay = (date, tokens) => ({ date: date, tokens: tokens })

// ---- dot metrics: sqrt ramp, bounds, monotonicity --------------------------
assert(Punchcard.dotMetrics(0, 100).size01 === 0 && Punchcard.dotMetrics(0, 100).alpha === 0, 'zero tokens -> no dot')
assert(Punchcard.dotMetrics(100, 100).size01 === 20 / 24, 'peak tokens -> full size fraction')
assert(Punchcard.dotMetrics(25, 100).size01 === (7 + 13 * 0.5) / 24, 'half tokens -> exact sqrt fraction')
assert(Punchcard.dotMetrics(100, 100).alpha === 1 && Punchcard.dotMetrics(1, 100).alpha > 0.35, 'alpha bounds respected')
const lo = Punchcard.dotMetrics(10, 100), hi = Punchcard.dotMetrics(50, 100)
assert(lo.size01 < hi.size01 && lo.alpha < hi.alpha, 'dot metrics monotonic in tokens')

// ---- sparse 7x24 semantics -------------------------------------------------
const sparse = Punchcard.parseUsageByHour([
  { weekday: 0, hour: 0, tokens: 5 },
  { weekday: 6, hour: 23, tokens: 7 },
])
assert(sparse.length === 2, 'sparse entries kept')
// The record field itself is untouched by the presentation change: storage
// stays Sun-first, and only the rendered rows reorder around today.
assert(sparse[0].weekday === 0 && sparse[0].hour === 0, 'the record stores Sunday 00:00 first')
assert(sparse[1].weekday === 6 && sparse[1].hour === 23, 'the record stores Saturday 23:00 last')

// ---- reading order: the week wraps around today, today renders last --------
const grid = Punchcard.punchcardWindow([
  { weekday: 0, hour: 0, tokens: 5 },   // Sun 00:00
  { weekday: 3, hour: 12, tokens: 50 }, // Wed 12:00
  { weekday: 5, hour: 21, tokens: 30 }, // Fri 21:00
  { weekday: 6, hour: 23, tokens: 7 },  // Sat 23:00
])
assert(!!grid && grid.rows.length === 7, 'the window renders all seven weekday rows')

// Today=Friday: the week runs Sat, Sun, Mon, Tue, Wed, Thu, Fri.
const friday = Punchcard.orderRowsForToday(grid.rows, 5)
assert(
  friday.rows.map(function(row) { return row.weekday }).join(",") === "6,0,1,2,3,4,5",
  'today=Friday renders Sat, Sun, Mon, Tue, Wed, Thu, Fri'
)
assert(friday.todayIndex === 6 && friday.rows[6].weekday === 5, 'today=Friday claims the last row as today')

// Wrap-around: today=Sunday renders Mon..Sun, today last.
const sunday = Punchcard.orderRowsForToday(grid.rows, 0)
assert(
  sunday.rows.map(function(row) { return row.weekday }).join(",") === "1,2,3,4,5,6,0",
  'today=Sunday renders Mon..Sun with Sunday last'
)
assert(sunday.todayIndex === 6 && sunday.rows[6].weekday === 0, 'today=Sunday claims the last row as today')

// Midweek: today=Wednesday renders Thu..Wed, today last.
const wednesday = Punchcard.orderRowsForToday(grid.rows, 3)
assert(
  wednesday.rows.map(function(row) { return row.weekday }).join(",") === "4,5,6,0,1,2,3",
  'today=Wednesday renders Thu..Wed with Wednesday last'
)
assert(wednesday.todayIndex === 6 && wednesday.rows[6].weekday === 3, 'today=Wednesday claims the last row as today')

// Presentation only: rows are reordered by reference — the cells are the
// grid's own arrays, untouched, so all-time data cannot drift.
assert(
  friday.rows[6].cells === grid.rows[5] && friday.rows[0].cells === grid.rows[6],
  'reordered rows carry the grid\'s own cell arrays, not copies'
)
assert(
  friday.rows[6].cells[21].tokens === 30
    && friday.rows[6].cells[21].weekday === 5 && friday.rows[6].cells[21].hour === 21
    && friday.rows[4].cells[12].tokens === 50 && friday.rows[4].cells[12].weekday === 3,
  'cell payloads keep their values and true weekday after the reorder'
)
assert(
  !!grid.rows[0][0] && !!grid.rows[3][12] && !!grid.rows[5][21] && !!grid.rows[6][23]
    && grid.rows[1][12] === null,
  'the original Sun-first grid is left exactly as the window built it'
)

// An out-of-range weekday is conservative: Sun-first, no row claimed.
const badToday = Punchcard.orderRowsForToday(grid.rows, 9)
assert(
  badToday.todayIndex === -1 && badToday.rows[0].weekday === 0 && badToday.rows[6].weekday === 6,
  'an out-of-range today keeps Sun-first and claims no row'
)

JS
