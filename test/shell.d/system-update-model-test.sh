#!/bin/bash

set -euo pipefail

# shellcheck source=test/shell.d/base-test.sh
source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const model = requireFromRoot('shell/plugins/system-update/Model.js')

const packages = model.parsePackageStatus(JSON.stringify({
  schemaVersion: 1,
  checked: '2026-07-18T20:00:00+02:00',
  checkedEpoch: 1784400000,
  available: true,
  state: 'updates',
  reason: '',
  count: 1,
  packages: [{ name: 'linux', installed: '6.1-1', target: '6.1-2' }]
}))
assertEqual(packages.state, 'updates', 'update center parses package state')
assertEqual(packages.count, 1, 'update center derives package count from validated rows')
assertEqual(packages.packages[0].target, '6.1-2', 'update center preserves package target version')

const malformedPackages = model.parsePackageStatus('{bad json')
assertEqual(malformedPackages.state, 'invalid', 'update center rejects malformed package JSON')
assertEqual(malformedPackages.count, 0, 'malformed package JSON cannot retain rows')

const inconsistentPackages = model.parsePackageStatus(JSON.stringify({
  schemaVersion: 1,
  available: true,
  state: 'current',
  packages: [{ name: 'linux', installed: '6.1-1', target: '6.1-2' }]
}))
assertEqual(inconsistentPackages.state, 'invalid', 'update center rejects package state and row mismatches')
assertEqual(inconsistentPackages.count, 0, 'inconsistent package state cannot expose action rows')

const themes = model.parseThemeStatus(JSON.stringify({
  schemaVersion: 1,
  scanId: 'scan',
  checkedEpoch: 1784400000,
  total: 2,
  reachable: 2,
  outdated: 1,
  actionable: 1,
  blocked: 0,
  degraded: false,
  themes: [
    { name: 'active', state: 'update', current: true, behind: 2, ahead: 0, reason: '', files: [], baseCommit: 'a', targetCommit: 'b' },
    { name: 'clean', state: 'clean', current: false, behind: 0, ahead: 0, reason: '', files: [], baseCommit: 'c', targetCommit: 'c' }
  ]
}))
assertEqual(themes.themes.length, 2, 'update center parses all user theme states')
assertEqual(model.themeStateLabel(themes.themes[0]), 'Update available', 'update center labels actionable theme state')
assert(model.themeStateDetail(themes.themes[0]).includes('2 reviewed commits'), 'update center explains reviewed commit count')

const special = model.parseThemeStatus(JSON.stringify({
  schemaVersion: 1,
  total: 1,
  themes: [{ name: 'bad', state: 'unknown-state' }]
}))
assertEqual(special.themes.length, 0, 'update center drops unknown theme states')
assertEqual(special.degraded, true, 'unknown theme states fail closed')

const inconsistentThemes = model.parseThemeStatus(JSON.stringify({
  schemaVersion: 1,
  total: 99,
  reachable: 99,
  outdated: 99,
  actionable: 99,
  blocked: 99,
  themes: [{ name: 'clean', state: 'clean', behind: 0, ahead: 0 }]
}))
assertEqual(inconsistentThemes.total, 1, 'update center derives theme totals from validated rows')
assertEqual(inconsistentThemes.outdated, 0, 'update center ignores contradictory theme summary counts')

const reviewOnlyTheme = model.parseThemeStatus(JSON.stringify({
  schemaVersion: 1,
  themes: [{ name: 'custom', state: 'local-edits', behind: 0, ahead: 0, reason: 'tracked-edits' }]
}))
assertEqual(reviewOnlyTheme.outdated, 0, 'local theme edits do not become fake remote updates')
assertEqual(reviewOnlyTheme.review, 1, 'local theme edits remain visible as review state')

assertEqual(model.preferredTab(1, 0, 1, false, ''), 'packages', 'package updates retain first priority')
assertEqual(model.preferredTab(0, 1, 0, false, ''), 'themes', 'outdated themes open the themes tab')
assertEqual(model.preferredTab(0, 0, 1, false, ''), 'themes', 'review-only themes open the themes tab')
assertEqual(model.preferredTab(0, 0, 0, true, ''), 'themes', 'incomplete theme checks open the themes tab')
assertEqual(model.preferredTab(0, 0, 0, false, ''), 'packages', 'clean state defaults to packages')
JS
