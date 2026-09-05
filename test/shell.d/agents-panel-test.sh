#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const panelSource = fs.readFileSync(root + '/shell/plugins/agents/Panel.qml', 'utf8')
const mainSource = fs.readFileSync(root + '/shell/plugins/agents/Main.qml', 'utf8')
const manifest = JSON.parse(fs.readFileSync(root + '/shell/plugins/agents/manifest.json', 'utf8'))

assert(/function launchAgent\(\)/.test(panelSource), 'agents panel launches the default agent')
assert(/root\.bar\.run\("omarchy-agent --pick"\)/.test(panelSource), 'agents panel uses the desktop agent launcher')
assert(/if \(buttonCode === Qt\.RightButton\) root\.launchAgent\(\)/.test(panelSource), 'agents right click launches the agent')
assert(/else if \(buttonCode === Qt\.MiddleButton\) root\.selectProvider\(root\.providerIndex \+ 1\)/.test(panelSource), 'agents middle click still advances the subscription')
assert(/else root\.toggle\(\)/.test(panelSource), 'agents left click still toggles the panel')
assert(!/if \(buttonCode === Qt\.RightButton\) root\.refreshNow\(\)/.test(panelSource), 'agents right click no longer refreshes')
assert(/function scheduleLimitResetNotifications\(\)/.test(mainSource), 'agents schedule future limit resets')
assert(/function announcePassedLimitResets\(\)/.test(mainSource), 'agents announce passed limit resets')
assert(/Quickshell\.execDetached\(\["omarchy-notification-send"/.test(mainSource), 'agents use the Omarchy notification helper')
assertEqual(manifest.barWidget.defaults.notifyOnLimitReset, true, 'agents enable reset notifications by default')
assert(manifest.barWidget.schema.some(field => field.key === 'notifyOnLimitReset' && field.type === 'boolean'), 'agents expose the reset notification toggle')
JS
