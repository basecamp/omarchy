#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const panelSource = fs.readFileSync(root + '/shell/plugins/agents/Panel.qml', 'utf8')

assert(/function launchAgent\(\)/.test(panelSource), 'agents panel launches the default agent')
assert(/root\.bar\.run\("omarchy-agent --pick"\)/.test(panelSource), 'agents panel uses the desktop agent launcher')
assert(/if \(buttonCode === Qt\.RightButton\) root\.launchAgent\(\)/.test(panelSource), 'agents right click launches the agent')
assert(/else if \(buttonCode === Qt\.MiddleButton\) root\.selectProvider\(root\.providerIndex \+ 1\)/.test(panelSource), 'agents middle click still advances the subscription')
assert(/else root\.toggle\(\)/.test(panelSource), 'agents left click still toggles the panel')
assert(!/if \(buttonCode === Qt\.RightButton\) root\.refreshNow\(\)/.test(panelSource), 'agents right click no longer refreshes')

const start = panelSource.indexOf('function windowIsLong')
const end = panelSource.indexOf('// The window that decides')
assert(start > 0 && end > start, 'agents panel exposes its limit-window helpers')
eval(panelSource.slice(start, end))

const untouchedFiveHour = { label: '5h window', percent: 0, resetsAt: '' }
assertDeepEqual(
  limitWindows({ providerId: 'codex', limits: [
    untouchedFiveHour,
    { label: 'Weekly (7-day)', percent: 0, resetsAt: '' },
    { label: 'Session (5-hour)', percent: 0.01, resetsAt: '' }
  ] }),
  [
    { title: 'Weekly', percent: 0, resetAt: '' },
    { title: 'Session', percent: 0.01, resetAt: '' }
  ],
  'agents panel hides only untouched Codex five-hour windows'
)
assertDeepEqual(
  limitWindows({ providerId: 'claude', limits: [untouchedFiveHour] }),
  [{ title: 'Session', percent: 0, resetAt: '' }],
  'agents panel leaves other providers unchanged'
)
JS
