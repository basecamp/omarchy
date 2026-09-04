#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const solver = requireFromRoot('shell/plugins/panels/clock/PlannerSolver.js')

function settings(availability) {
  return {
    timezone: 'Europe/Rome', availability, horizonDays: 14, slotMinutes: 15,
    solveSeconds: 5, priorityLowWeight: 1, priorityNormalWeight: 5, priorityHighWeight: 25,
    cognitiveEnabled: false,
    lowWindowStart: '00:00', lowWindowEnd: '00:00', lowOutsidePenalty: 0,
    mediumWindowStart: '00:00', mediumWindowEnd: '00:00', mediumOutsidePenalty: 0,
    highWindowStart: '00:00', highWindowEnd: '00:00', highOutsidePenalty: 0,
    highStreakLimit: 1, recoveryMinutes: 30, excessHighPenalty: 60
  }
}

function task(id, title, priority = 'normal') {
  return { id, title, durationMinutes: 30, priority, cognitiveLoad: 'medium',
    earliestAt: null, deadlineKind: 'none', deadlineAt: null, state: 'inbox',
    linkedEventId: null }
}

function request(overrides = {}) {
  return Object.assign({ requestId: 'solver-test', baseInputRevision: 4,
    now: '2026-09-04T08:00:00Z', settings: settings({ friday: [{ start: '09:00', end: '17:00' }] }),
    events: [], tasks: [], dependencies: [] }, overrides)
}

let proposal = solver.solve(request({ tasks: [task('one', 'One')] }))
assertEqual(proposal.items[0].scheduled, true, 'planner schedules an inbox task in weekly availability')
assertEqual(new Date(proposal.items[0].startAt).toISOString(), '2026-09-04T08:00:00.000Z', 'planner uses configured timezone availability')

proposal = solver.solve(request({
  events: [{ id: 'busy', title: 'Busy', startAt: '2026-09-04T08:00:00Z', endAt: '2026-09-04T09:00:00Z', timezone: 'Europe/Rome', rrule: null }],
  tasks: [task('blocked', 'Blocked')]
}))
assertEqual(proposal.items[0].scheduled, true, 'planner moves a task around a busy event')
assertEqual(new Date(proposal.items[0].startAt).toISOString(), '2026-09-04T09:00:00.000Z', 'planner does not overlap a busy event')
assertEqual(proposal.items[0].busyBlockers[0], 'busy', 'planner reports the busy event as a blocker')

let hard = task('hard', 'Hard deadline')
hard.deadlineKind = 'hard'
hard.deadlineAt = '2026-09-04T08:15:00Z'
proposal = solver.solve(request({ tasks: [hard] }))
assertEqual(proposal.items[0].scheduled, false, 'planner leaves a task unscheduled when its hard deadline is impossible')
assertEqual(proposal.items[0].diagnostics.outcome, 'no_hard_feasible_slot', 'planner explains an impossible hard deadline')

proposal = solver.solve(request({ tasks: [task('first', 'First', 'high'), task('second', 'Second')], dependencies: [{ fromTaskId: 'first', toTaskId: 'second' }] }))
assertEqual(proposal.items.every(item => item.scheduled), true, 'planner schedules a dependency chain')
assert(new Date(proposal.items.find(item => item.taskId === 'first').endAt) <= new Date(proposal.items.find(item => item.taskId === 'second').startAt), 'planner orders dependent tasks')

const dailyEvent = { id: 'daily', title: 'Daily', startAt: '2026-09-04T07:00:00Z', endAt: '2026-09-04T08:00:00Z', timezone: 'Europe/Rome', rrule: 'FREQ=DAILY;COUNT=2' }
proposal = solver.solve(request({
  events: [dailyEvent],
  tasks: [task('recurring', 'Recurring')]
}))
assertEqual(solver.expandBusy([dailyEvent], Date.parse('2026-09-04T00:00:00Z'), Date.parse('2026-09-20T00:00:00Z')).length, 2, 'planner expands daily recurrence in event timezone')
assertEqual(proposal.items[0].scheduled, true, 'planner schedules around recurring busy time')
JS
