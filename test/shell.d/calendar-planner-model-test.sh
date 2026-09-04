#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const planner = requireFromRoot('shell/plugins/panels/clock/PlannerModel.js')

const tasks = [
  { id: 'low', title: 'Later', priority: 'low', cognitiveLoad: 'low', durationMinutes: 15 },
  { id: 'normal', title: 'Middle', priority: 'normal', cognitiveLoad: 'medium', durationMinutes: 60 },
  { id: 'high', title: 'First', priority: 'high', cognitiveLoad: 'high', durationMinutes: 90 }
]
assertDeepEqual(
  planner.sortedTasks(tasks).map(task => task.id),
  ['high', 'normal', 'low'],
  'planner sorts tasks by priority before stable labels'
)
assertEqual(planner.formatDuration(90), '1h 30m', 'planner formats mixed-hour durations')
assertEqual(planner.formatDuration(45), '45m', 'planner formats minute durations')
assertEqual(planner.priorityLabel('high'), 'High', 'planner formats priority labels')
assertEqual(planner.loadLabel('medium'), 'Medium', 'planner formats cognitive labels')

const events = [
  { id: 'later', title: 'Later', startAt: '2026-09-04T12:00:00+02:00', endAt: '2026-09-04T13:00:00+02:00' },
  { id: 'first', title: 'First', startAt: '2026-09-04T09:00:00+02:00', endAt: '2026-09-04T10:00:00+02:00' }
]
assertDeepEqual(planner.sortedEvents(events).map(event => event.id), ['first', 'later'], 'planner orders events by start')
assertDeepEqual(planner.eventsForDay(events, '2026-09-04', 'Europe/Rome').map(event => event.id), ['first', 'later'], 'planner groups events in the configured timezone')
assertDeepEqual(planner.eventMarkers(events, 'Europe/Rome'), { '2026-09-04': 2 }, 'planner counts event markers by local day')

const proposal = {
  items: [
    { taskId: 'b', scheduled: false, diagnostics: { outcome: 'no_hard_feasible_slot' } },
    { taskId: 'a', scheduled: true, startAt: '2026-09-04T09:00:00+02:00', diagnostics: { outcome: 'scheduled' } }
  ]
}
assertDeepEqual(planner.proposalSummary(proposal), { scheduled: 1, total: 2, unscheduled: 1 }, 'planner summarizes proposal outcomes')
assertDeepEqual(planner.scheduledItems(proposal).map(item => item.taskId), ['a'], 'planner sorts scheduled proposal items')
assertEqual(planner.outcomeLabel(proposal.items[0]), 'No feasible slot', 'planner maps no-slot diagnostics')
assert(planner.explanation(proposal.items[0]).length > 0, 'planner exposes explanation copy')
assertEqual(planner.solveStateLabel('configuration_needed'), 'Configuration needed', 'planner formats service states')
assertDeepEqual(
  planner.applicabilityReasons({ status: 'stale', staleReason: 'inputs_changed', applicabilityReasons: [] }, 3),
  ['Planning inputs changed; generate a new proposal before applying.', 'Planning inputs changed since this proposal was generated.'],
  'planner explains stale proposals'
)
JS
