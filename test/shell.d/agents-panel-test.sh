#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const panelSource = fs.readFileSync(root + '/shell/plugins/agents/Panel.qml', 'utf8')
const mainSource = fs.readFileSync(root + '/shell/plugins/agents/Main.qml', 'utf8')
const agents = requireFromRoot('shell/plugins/agents/AgentsModel.js')

assertEqual(agents.totalTokens({ modelUsage: { model: { inputTokens: 1, outputTokens: 2, cacheReadInputTokens: 3, cacheCreationInputTokens: 4 } } }), 10, 'agents total every token category')
assertDeepEqual(agents.sortByUsage([
  { providerId: 'antigravity', providerName: 'Antigravity', totalPrompts: 4, modelUsage: { gemini: { inputTokens: 4 } } },
  { providerId: 'claude', providerName: 'Claude Code', totalPrompts: 20, modelUsage: { claude: { inputTokens: 100 } } },
  { providerId: 'codex', providerName: 'Codex', totalPrompts: 10, modelUsage: { codex: { inputTokens: 50 } } },
  { providerId: 'fireworks', providerName: 'Fireworks', totalPrompts: 0, modelUsage: {} }
]).map(provider => provider.providerId), ['claude', 'codex', 'antigravity', 'fireworks'], 'agents sort left to right by total usage')
assertDeepEqual(agents.sortByUsage([
  { providerId: 'zeta', providerName: 'Zeta', totalPrompts: 1, modelUsage: { model: { inputTokens: 1 } } },
  { providerId: 'same-b', providerName: 'Same', totalPrompts: 1, modelUsage: { model: { inputTokens: 1 } } },
  { providerId: 'prompts', providerName: 'Prompts', totalPrompts: 2, modelUsage: { model: { inputTokens: 1 } } },
  { providerId: 'alpha', providerName: 'Alpha', totalPrompts: 1, modelUsage: { model: { inputTokens: 1 } } },
  { providerId: 'same-a', providerName: 'Same', totalPrompts: 1, modelUsage: { model: { inputTokens: 1 } } }
]).map(provider => provider.providerId), ['prompts', 'alpha', 'same-a', 'same-b', 'zeta'], 'agents break usage ties by prompts, provider name, then id')
assert(/import "AgentsModel\.js" as AgentsModel/.test(mainSource), 'agents panel imports its usage ordering model')
assert(/return AgentsModel\.sortByUsage\(result\)/.test(mainSource), 'agents panel orders enabled providers by usage')

assert(/function launchAgent\(\)/.test(panelSource), 'agents panel launches the default agent')
assert(/root\.bar\.run\("omarchy-agent --pick"\)/.test(panelSource), 'agents panel uses the desktop agent launcher')
assert(/if \(buttonCode === Qt\.RightButton\) root\.launchAgent\(\)/.test(panelSource), 'agents right click launches the agent')
assert(/else if \(buttonCode === Qt\.MiddleButton\) root\.selectProvider\(root\.providerIndex \+ 1\)/.test(panelSource), 'agents middle click still advances the subscription')
assert(/else root\.toggle\(\)/.test(panelSource), 'agents left click still toggles the panel')
assert(!/if \(buttonCode === Qt\.RightButton\) root\.refreshNow\(\)/.test(panelSource), 'agents right click no longer refreshes')
JS
