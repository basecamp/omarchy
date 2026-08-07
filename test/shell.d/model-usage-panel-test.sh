#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const vm = require('vm')

const panelSource = fs.readFileSync(path.join(root, 'shell/plugins/model-usage/Panel.qml'), 'utf8')
const mainSource = fs.readFileSync(path.join(root, 'shell/plugins/model-usage/Main.qml'), 'utf8')
const cursorSource = fs.readFileSync(path.join(root, 'shell/plugins/model-usage/providers/Cursor.qml'), 'utf8')

function extractFunction(source, name) {
  const needle = `function ${name}(`
  const start = source.indexOf(needle)
  if (start < 0) fail(`function ${name} exists in source`)
  let i = source.indexOf('{', start)
  let depth = 0
  for (; i < source.length; i++) {
    const ch = source[i]
    if (ch === '{') depth++
    else if (ch === '}') {
      depth--
      if (depth === 0) return source.slice(start, i + 1)
    }
  }
  fail(`function ${name} has a closed body`)
}

function loadHelpers(source, names, extras = {}) {
  const sandbox = {
    Math,
    String,
    Number,
    Date,
    Array,
    Object,
    isFinite,
    console,
    ...extras
  }
  vm.createContext(sandbox)
  for (const name of names) {
    vm.runInContext(extractFunction(source, name), sandbox)
  }
  return sandbox
}

assert(
  /hasDayChart:[\s\S]*?provider\.hasLocalStats !== false[\s\S]*?weekPeak\(provider\) > 0/.test(panelSource),
  'panel day chart requires hasLocalStats and a positive week peak'
)
assert(
  /hasModelChart:[\s\S]*?provider\.hasLocalStats !== false/.test(panelSource),
  'panel model chart requires hasLocalStats'
)
assert(
  /showReset:\s*!root\.limitsResetInHeader/.test(panelSource),
  'panel hides per-row resets when LIMITS header owns the shared countdown'
)
assert(
  !/Timer\s*\{\s*interval:\s*5\s*\*\s*60\s*\*\s*1000/.test(cursorSource),
  'Cursor provider does not keep a fixed five-minute refresh timer'
)

const nowMs = Date.parse('2030-01-01T00:00:00.000Z') - (2 * 60 * 60 * 1000)
const panel = loadHelpers(panelSource, [
  'windowIsLong',
  'windowSpanMs',
  'windowTitle',
  'limitWindow',
  'limitWindows',
  'bindingWindow',
  'resetMsFor',
  'formatDuration',
  'limitsShareReset',
  'sharedLimitsResetText',
  'weekPeak'
], { root: { nowMs } })

function hasDayChart(provider, peakFn) {
  return !!provider
    && provider.hasLocalStats !== false
    && peakFn(provider) > 0
}

function hasModelChart(provider, models) {
  return !!provider
    && provider.hasLocalStats !== false
    && models.length > 0
}

const main = loadHelpers(mainSource, [
  'numberValue',
  'dateString',
  'recentDateStrings',
  'emptyTokenBucket',
  'addObjectNumbers',
  'safeDeviceId',
  'providerHasData',
  'aggregateSnapshots'
], {
  Quickshell: { env() { return '' } },
  root: { detectedHostname: 'test-host' }
})

// Manual: signed-out / missing Cursor stays self-hidden like Claude/Codex
const missingCursor = {
  totalPrompts: 0,
  totalSessions: 0,
  activeDays: 0,
  rateLimitPercent: -1,
  secondaryRateLimitPercent: -1
}
assertEqual(main.providerHasData(missingCursor), false, 'missing/signed-out Cursor has no display data')

const signedInCursor = {
  totalPrompts: 0,
  totalSessions: 0,
  activeDays: 0,
  rateLimitPercent: 0.125,
  secondaryRateLimitPercent: 0.4
}
assertEqual(main.providerHasData(signedInCursor), true, 'signed-in Cursor with meters has display data')

// Manual: Claude session vs weekly still shows per-row resets (no shared LIMITS hoist)
const claudeWindows = panel.limitWindows({
  rateLimitPercent: 0.2,
  rateLimitLabel: 'Session (5-hour)',
  rateLimitResetAt: '2030-01-01T01:00:00.000Z',
  secondaryRateLimitPercent: 0.5,
  secondaryRateLimitLabel: 'Weekly',
  secondaryRateLimitResetAt: '2030-01-05T00:00:00.000Z'
})
assertEqual(panel.limitsShareReset(claudeWindows), false, 'Claude session vs weekly does not share one reset')
assertEqual(panel.sharedLimitsResetText(claudeWindows), '', 'Claude leaves LIMITS header without a shared countdown')

// Manual: Cursor billing-cycle end appears once in the LIMITS header
const sharedReset = '2030-01-01T00:00:00.000Z'
const cursorWindows = panel.limitWindows({
  rateLimitPercent: 0.125,
  rateLimitLabel: 'Cursor Models',
  rateLimitResetAt: sharedReset,
  secondaryRateLimitPercent: 0.4,
  secondaryRateLimitLabel: 'Other Models',
  secondaryRateLimitResetAt: sharedReset
})
assertEqual(cursorWindows.length, 2, 'Cursor exposes both period meters')
assertEqual(panel.limitsShareReset(cursorWindows), true, 'Cursor pools share one billing-cycle reset')
assertEqual(
  panel.sharedLimitsResetText(cursorWindows),
  'Resets in 2h 0m',
  'Cursor LIMITS header shows the shared billing-cycle countdown once'
)

// Manual: with syncMode On, Cursor still hides TOKENS BY DAY / TOKENS BY MODEL
const aggregated = main.aggregateSnapshots([{
  deviceId: 'laptop',
  providers: {
    cursor: {
      providerName: 'Cursor',
      ready: true,
      hasLocalStats: false,
      todayPrompts: 0,
      todaySessions: 0,
      todayTotalTokens: 0,
      todayTokensByModel: {},
      recentDays: [],
      totalPrompts: 0,
      totalSessions: 0,
      activeDays: 0,
      activeDates: [],
      modelUsage: {},
      rateLimitPercent: 0.125,
      secondaryRateLimitPercent: 0.4
    }
  }
}])

const syncedCursor = aggregated.providers.cursor
assertEqual(syncedCursor.hasLocalStats, false, 'sync aggregation preserves Cursor hasLocalStats false')
assertEqual(syncedCursor.recentDays.length, 7, 'sync aggregation still synthesizes seven recentDays rows')
assertEqual(hasDayChart(syncedCursor, panel.weekPeak), false, 'Cursor hides TOKENS BY DAY under syncMode')
assertEqual(
  hasModelChart(syncedCursor, Object.keys(syncedCursor.modelUsage || {})),
  false,
  'Cursor hides TOKENS BY MODEL under syncMode'
)

const zeroWeek = {
  hasLocalStats: true,
  recentDays: syncedCursor.recentDays
}
assertEqual(hasDayChart(zeroWeek, panel.weekPeak), false, 'all-zero recentDays does not count as day history')

const withHistory = {
  hasLocalStats: true,
  recentDays: syncedCursor.recentDays.map((day, index) => (
    index === syncedCursor.recentDays.length - 1
      ? { ...day, messageCount: 1200 }
      : day
  ))
}
assertEqual(hasDayChart(withHistory, panel.weekPeak), true, 'positive day totals still show the day chart')
JS
