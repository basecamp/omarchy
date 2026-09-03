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

const cacheStart = panelSource.indexOf('function inputCacheStats')
const cacheEnd = panelSource.indexOf('function cacheDetailText')
const cachePercentStart = panelSource.indexOf('function inputCachePercent')
assert(cachePercentStart > 0 && cacheStart > cachePercentStart && cacheEnd > cacheStart, 'agents panel exposes its input-cache helpers')
eval(panelSource.slice(cachePercentStart, cacheEnd))

assertDeepEqual(
  inputCacheStats({
    providerId: 'claude',
    modelUsage: {
      opus: { inputTokens: 10, outputTokens: 500, cacheReadInputTokens: 80, cacheCreationInputTokens: 10 },
      haiku: { inputTokens: 5, outputTokens: 500, cacheReadInputTokens: 95, cacheCreationInputTokens: 0 }
    }
  }),
  { percent: 0.875, input: 15, cacheRead: 175, cacheWrite: 10, totalInput: 200 },
  'agents panel calculates Claude cache hits from input tokens without counting output'
)

assertDeepEqual(
  inputCacheStats({
    providerId: 'codex',
    modelUsage: {
      'gpt-5': { inputTokens: 20, outputTokens: 40, cacheReadInputTokens: 80, cacheCreationInputTokens: 0 }
    }
  }),
  { percent: 0.8, input: 20, cacheRead: 80, cacheWrite: 0, totalInput: 100 },
  'agents panel calculates Codex cache hits from its normalized token split'
)

assertEqual(inputCacheStats({ providerId: 'claude', modelUsage: {} }), null, 'agents panel hides cache metrics without input data')
assertEqual(inputCacheStats({
  providerId: 'fireworks',
  modelUsage: { kimi: { inputTokens: 20, cacheReadInputTokens: 80 } }
}), null, 'agents panel limits the cache metric to Claude and Codex')

const modelStart = panelSource.indexOf('function modelRows')
const modelEnd = panelSource.indexOf('// Only speaks up')
assert(modelStart > 0 && modelEnd > modelStart, 'agents panel exposes its model helpers')
const usage = { friendlyModelName: value => value, formatTokenCount: value => String(value) }
eval(panelSource.slice(modelStart, modelEnd))
const model = modelRows({ modelUsage: {
  'gpt-test': { inputTokens: 20, outputTokens: 40, cacheReadInputTokens: 80, cacheCreationInputTokens: 0 }
} })[0]
assertEqual(model.cachePercent, 0.8, 'agents panel gives each model its cache-hit percentage')
assert(/80% of input cached/.test(modelTooltip(model)), 'agents model tooltip shows its cache-hit percentage')
JS
