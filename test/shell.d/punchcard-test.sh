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
assert(sparse[0].weekday === 0 && sparse[0].hour === 0, 'first cell is Sunday 00:00')
assert(sparse[1].weekday === 6 && sparse[1].hour === 23, 'last cell is Saturday 23:00')

JS
