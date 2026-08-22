#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const Model = requireFromRoot('shell/plugins/panels/backup/Model.js')

const now = Date.parse('2026-08-22T12:00:00Z')
const hourAgo = now / 1000 - 3600

function status(overrides) {
  return Model.parseStatus(JSON.stringify(Object.assign({
    phase: 'idle',
    last_backup: {time: hourAgo, snapshot: 'abcd1234', result: 'complete', error: '', unreadable: []},
    last_complete: {time: hourAgo, snapshot: 'abcd1234'},
    destination: {label: 'photos at s3.example.com', kind: 's3', offsite: true},
    repository: {size_bytes: 2500000000, snapshot_count: 42}
  }, overrides)))
}

assertEqual(Model.parseStatus('').phase, 'unconfigured', 'an absent status file reads as unconfigured')
assertEqual(Model.parseStatus('{oh no').phase, 'unconfigured', 'a corrupt status file does not throw')

assertEqual(
  Model.heroMeta(status({}), 24, now),
  'Backed up 1 hour ago',
  'the hero says when the last backup was'
)
assertEqual(
  Model.heroMeta(status({phase: 'running', progress: {percent: 42}}), 24, now),
  'Backing up 42%',
  'a running backup shows its progress'
)
assertEqual(
  Model.heroMeta(status({phase: 'paused', pause: {until: now / 1000 + 1800}}), 24, now),
  'Paused for 30 more minutes',
  'a timed pause counts down'
)
assertEqual(
  Model.heroMeta(status({phase: 'paused', pause: {until: 0}}), 24, now),
  'Paused until resumed',
  'an open-ended pause says so'
)

assertEqual(Model.repositoryText(status({})), '2.5 GB in 42 backups', 'the repository line is sizes, not bytes')

// A failed run, a partial one, and a backup that quietly stopped happening are
// the three things worth colouring the bar for. A pause is a choice.
assert(!Model.attention(status({}), 24, now), 'a healthy backup does not ask for attention')
assert(
  Model.attention(status({last_backup: {time: hourAgo, result: 'failed', error: 'no route to host'}}), 24, now),
  'a failed run asks for attention'
)
assert(
  Model.attention(status({last_backup: {time: hourAgo, result: 'partial', unreadable: ['/home/x/vault']}}), 24, now),
  'a partial run asks for attention'
)
assert(
  Model.attention(status({last_complete: {time: now / 1000 - 90000}}), 24, now),
  'a day without a complete backup asks for attention'
)
assert(
  !Model.attention(status({phase: 'paused', last_complete: {time: now / 1000 - 90000}}), 24, now),
  'a pause is not a problem, however old the last backup is'
)
assert(!Model.attention(Model.parseStatus(''), 24, now), 'an unconfigured machine is not nagged')

assertEqual(
  Model.problem(status({last_backup: {time: hourAgo, result: 'partial', unreadable: ['/home/x/vault', '/home/x/db']}})),
  'Could not read 2 paths, starting with /home/x/vault',
  'a partial backup names what it could not read'
)
assertEqual(
  Model.problem(status({last_skip: {time: now / 1000, reason: 'the backup disk is not mounted'}})),
  'Last run skipped: the backup disk is not mounted',
  'a skip more recent than the last backup is surfaced'
)
assertEqual(Model.problem(status({})), '', 'a healthy backup reports no problem')
JS
