#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const panelSource = fs.readFileSync(root + '/shell/plugins/agents/Panel.qml', 'utf8')
const mainSource = fs.readFileSync(root + '/shell/plugins/agents/Main.qml', 'utf8')
const agentSource = fs.readFileSync(root + '/shell/plugins/agents/Agent.qml', 'utf8')

assert(/function launchAgent\(\)/.test(panelSource), 'agents panel launches the default agent')
assert(/root\.bar\.run\("omarchy-agent --pick"\)/.test(panelSource), 'agents panel uses the desktop agent launcher')
assert(/source: root\.provider \? Qt\.resolvedUrl\("assets\/" \+ root\.provider\.providerId \+ "\.svg"\) : ""/.test(panelSource), 'agents bar icon uses the current provider svg')
assert(/property var candidates: root\.iconCandidatesForProvider\(root\.provider, root\.surface\)/.test(panelSource), 'agents panel header resolves the provider svg')
assert(!/text: button\.text/.test(panelSource), 'agents panel never falls back to the generic bar glyph')
assert(/if \(buttonCode === Qt\.RightButton\) root\.launchAgent\(\)/.test(panelSource), 'agents right click launches the agent')
assert(/else if \(buttonCode === Qt\.MiddleButton\) root\.selectProvider\(root\.providerIndex \+ 1\)/.test(panelSource), 'agents middle click still advances the subscription')
assert(/else root\.toggle\(\)/.test(panelSource), 'agents left click still toggles the panel')
assert(!/if \(buttonCode === Qt\.RightButton\) root\.refreshNow\(\)/.test(panelSource), 'agents right click no longer refreshes')

assert(/usage\.reloadRecords\(\)/.test(panelSource), 'agents panel re-reads records when opened')
assert(/usage\.rescanAgents\(\)/.test(panelSource), 'agents panel rescans for new records when opened')
assert(/function reloadRecords\(\)/.test(mainSource), 'agents main exposes a record reload')
assert(/atomicWrites: true/.test(agentSource), 'agents record watcher detects atomic replacements')
assert(/function reload\(\)/.test(agentSource), 'agents record watcher exposes a manual reload')
JS
