#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const State = requireFromRoot('shell/plugins/panels/clock/State.js')

function assertThrows(fn, description) {
  let threw = false
  try { fn() } catch (error) { threw = true }
  assert(threw, description)
}

const defaults = State.defaultSettings()
assertDeepEqual(defaults, {
  timezone: '',
  availability: {},
  horizonDays: 14,
  slotMinutes: 15,
  solveSeconds: 5,
  priorityLowWeight: 1,
  priorityNormalWeight: 5,
  priorityHighWeight: 25,
  cognitiveEnabled: false,
  lowWindowStart: '00:00',
  lowWindowEnd: '00:00',
  lowOutsidePenalty: 0,
  mediumWindowStart: '00:00',
  mediumWindowEnd: '00:00',
  mediumOutsidePenalty: 0,
  highWindowStart: '00:00',
  highWindowEnd: '00:00',
  highOutsidePenalty: 0,
  highStreakLimit: 1,
  recoveryMinutes: 30,
  excessHighPenalty: 60,
}, 'calendar settings expose every documented default')

assertEqual(State.baseState().schemaVersion, 1, 'calendar state starts at schema version one')
assertEqual(State.baseState().inputRevision, 0, 'calendar state starts at input revision zero')
assertDeepEqual(State.normalizeState(null).events, [], 'missing state recovers with empty events')
assertDeepEqual(State.normalizeState({settings: {horizonDays: 90}}).settings.horizonDays, 90, 'loaded settings are deeply normalized')
assertDeepEqual(State.normalizeState({settings: {availability: {monday: [{start: '9:00', end: '17:00'}]}}}).settings.availability, {monday: [{start: '09:00', end: '17:00'}]}, 'availability clocks are normalized')
assertDeepEqual(State.normalizeState({settings: {availability: {noday: [{start: '09:00', end: '17:00'}]}}}).settings.availability, {}, 'unknown loaded weekdays do not enter normalized state')

assertEqual(State.normalizeClock('9:05'), '09:05', 'clock values accept single-digit input for normalization')
assertEqual(State.normalizeClock('09:60'), null, 'clock values reject minutes outside the day')
assert(State.validTimezone('Europe/Rome'), 'IANA timezone names are accepted')
assert(State.validTimezone('UTC'), 'UTC is accepted as a valid timezone')
assert(!State.validTimezone('Not/A_Timezone'), 'invalid timezone names are rejected')

const invalidReady = State.settingsReady({timezone: 'Europe/Rome', availability: {monday: [{start: '09:00', end: '17:00'}]}})
assert(invalidReady.ok, 'configured timezone and weekly availability are solve-ready')
assert(!State.settingsReady({timezone: 'Europe/Rome', availability: {}}).ok, 'empty weekly availability is not solve-ready')
assert(!State.validateSettings({timezone: 'Europe/Rome', availability: {monday: [{start: '17:00', end: '09:00'}]}}, false).ok, 'backwards availability windows are rejected')
assert(!State.validateSettings({timezone: 'Europe/Rome', availability: {funday: [{start: '09:00', end: '17:00'}]}}, false).ok, 'unknown availability weekdays are rejected')
assert(!State.validateSettings({timezone: 'Europe/Rome', availability: {monday: [{start: '09:00', end: '17:00'}]}, horizonDays: 0}, false).ok, 'settings enforce the horizon lower bound')
assert(!State.validateSettings({timezone: 'Europe/Rome', availability: {monday: [{start: '09:00', end: '17:00'}]}, slotMinutes: 121}, false).ok, 'settings enforce the slot-size upper bound')

const first = State.newId('task', 1700000000000, 'abc')
const second = State.newId('task', 1700000000000, 'def')
assert(/^task-1700000000000-\d+-abc$/.test(first), 'local ids carry kind, time, counter, and random suffix')
assert(first !== second, 'local ids remain unique within a process')

const manualEvent = {
  id: 'event-manual', title: 'Busy', startAt: '2026-09-07T09:00:00+02:00', endAt: '2026-09-07T10:00:00+02:00', timezone: 'Europe/Rome'
}
let state = State.addEvent(State.baseState(), manualEvent, '2026-09-01T10:00:00Z')
assertEqual(state.inputRevision, 1, 'event creation advances the input revision')
assertEqual(state.events[0].origin, 'manual', 'events default to manual origin')
const eventFingerprint = State.problemFingerprint(state)
state = State.updateEvent(state, 'event-manual', {title: 'Busy updated'}, '2026-09-01T10:01:00Z')
assertEqual(state.inputRevision, 2, 'event edits advance the input revision')
assert(State.problemFingerprint(state) !== eventFingerprint, 'problem fingerprints change with planning inputs')

state = State.addTask(state, {id: 'task-a', title: 'First', durationMinutes: 30}, '2026-09-01T10:02:00Z')
state = State.addTask(state, {id: 'task-b', title: 'Second', durationMinutes: 30}, '2026-09-01T10:03:00Z')
assertEqual(state.tasks[0].state, 'inbox', 'new tasks enter the inbox')
state = State.addDependency(state, 'task-a', 'task-b')
assertEqual(state.dependencies.length, 1, 'dependency creation is persisted')
const sameDependencies = State.replaceTaskDependencies(state, 'task-b', ['task-a'])
assertEqual(sameDependencies.inputRevision, state.inputRevision, 'unchanged dependencies do not advance the revision')
assertThrows(() => State.addDependency(state, 'task-b', 'task-a'), 'dependency cycles are rejected')
assertThrows(() => State.addDependency(state, 'task-a', 'task-a'), 'self-dependencies are rejected')
assertThrows(() => State.addDependency(state, 'task-a', 'missing'), 'dependencies require existing task ids')
state = State.deleteDependency(state, 'task-a', 'task-b')
assertEqual(state.dependencies.length, 0, 'dependency deletion is persisted')
state = State.replaceTaskDependencies(state, 'task-b', ['task-a'])
assertEqual(state.dependencies[0].fromTaskId, 'task-a', 'task editor replaces incoming dependencies')
assertThrows(() => State.replaceTaskDependencies(state, 'task-a', ['task-b']), 'task editor rejects dependency cycles')
state = State.replaceTaskDependencies(state, 'task-b', [])
assertEqual(state.dependencies.length, 0, 'task editor can clear dependencies')

const beforeSettingsRevision = state.inputRevision
state = State.updateSettings(state, {timezone: 'Europe/Rome', availability: {monday: [{start: '09:00', end: '17:00'}]}}, '2026-09-01T10:04:00Z')
assertEqual(state.inputRevision, beforeSettingsRevision + 1, 'settings changes advance the input revision')
assert(State.settingsReady(state.settings).ok, 'settings reducer leaves a ready configuration')

const proposal = {
  id: 'proposal-1', status: 'ready', baseInputRevision: state.inputRevision, requestId: 'request-1',
  horizonStart: '2026-09-07T00:00:00+02:00', horizonDays: 14, timezone: 'Europe/Rome', score: {hard: 0, medium: 0, soft: 0},
  items: [
    {taskId: 'task-a', startAt: '2026-09-07T09:00:00+02:00', endAt: '2026-09-07T09:30:00+02:00', scheduled: true},
    {taskId: 'task-b', scheduled: false, diagnostics: {outcome: 'no_hard_feasible_slot'}}
  ], applicabilityReasons: []
}
state = State.writeProposal(state, proposal)
assertEqual(state.inputRevision, proposal.baseInputRevision, 'writing derived proposal output does not advance input revision')
assertEqual(state.proposal.status, 'ready', 'written proposals are ready for review')
state = State.updateTask(state, 'task-a', {title: 'First changed'}, '2026-09-01T10:05:00Z')
assertEqual(state.proposal.status, 'stale', 'input changes stale the current proposal')
assertThrows(() => State.applyProposal(state), 'stale proposals cannot be applied')

state = State.writeProposal(state, {...proposal, baseInputRevision: state.inputRevision, requestId: 'request-2'})
const appliedRevision = state.inputRevision + 1
state = State.applyProposal(state, '2026-09-01T10:06:00Z')
assertEqual(state.inputRevision, appliedRevision, 'applying a proposal advances the input revision exactly once')
assertEqual(state.proposal.status, 'applied', 'applying a proposal marks it applied')
assertEqual(state.tasks.find(task => task.id === 'task-a').state, 'applied', 'scheduled tasks become applied')
assertEqual(state.tasks.find(task => task.id === 'task-b').state, 'inbox', 'unscheduled tasks remain in the inbox')
assertEqual(state.events.filter(event => event.origin === 'planner').length, 1, 'applying creates one linked planner event')

const linkedEventId = state.tasks.find(task => task.id === 'task-a').linkedEventId
state = State.deleteEvent(state, linkedEventId)
assertEqual(state.tasks.find(task => task.id === 'task-a').state, 'missing_event', 'deleting a linked planner event marks its task missing_event')
assertThrows(() => State.updateTask(state, 'task-a', {title: 'unsafe edit'}), 'applied task edits are locked')
state = State.returnToInbox(state, 'task-a', '2026-09-01T10:07:00Z')
assertEqual(state.tasks.find(task => task.id === 'task-a').state, 'inbox', 'return to inbox is explicit')
assertEqual(state.events.filter(event => event.taskId === 'task-a').length, 0, 'return to inbox removes only the linked planner event')

const stableA = State.problemFingerprint(state)
const stableB = State.problemFingerprint(State.normalizeState(JSON.parse(JSON.stringify(state))))
assertEqual(stableA, stableB, 'problem fingerprints are stable across JSON round trips')
JS
