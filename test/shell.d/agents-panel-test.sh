#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const panelSource = fs.readFileSync(root + '/shell/plugins/agents/Panel.qml', 'utf8')

assert(/defaultAgentPath: home \+ "\/\.config\/omarchy\/defaults\/agent"/.test(panelSource), 'agents panel reads the configured default agent')
assert(/path: root\.defaultAgentPath[\s\S]{0,160}?watchChanges: true[\s\S]{0,160}?onFileChanged: reload\(\)/.test(panelSource), 'agents panel watches default-agent changes')
assert(/onLoaded: root\.defaultAgentId = String\(text\(\) \|\| ""\)\.trim\(\)/.test(panelSource), 'agents panel loads the default agent id')
assert(/providerId === selectedProviderId\) return i[\s\S]{0,160}?providerId === defaultAgentId\) return j[\s\S]{0,80}?return 0/.test(panelSource), 'agents panel prefers an explicit selection, then the configured default')
assert(/function launchAgent\(\)/.test(panelSource), 'agents panel launches the default agent')
assert(/root\.bar\.run\("omarchy-agent --pick"\)/.test(panelSource), 'agents panel uses the desktop agent launcher')
assert(/if \(buttonCode === Qt\.RightButton\) root\.launchAgent\(\)/.test(panelSource), 'agents right click launches the agent')
assert(/else if \(buttonCode === Qt\.MiddleButton\) root\.selectProvider\(root\.providerIndex \+ 1\)/.test(panelSource), 'agents middle click still advances the subscription')
assert(/else root\.toggle\(\)/.test(panelSource), 'agents left click still toggles the panel')
assert(!/if \(buttonCode === Qt\.RightButton\) root\.refreshNow\(\)/.test(panelSource), 'agents right click no longer refreshes')
JS
