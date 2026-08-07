#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const panelSource = fs.readFileSync(root + '/shell/plugins/agents/Panel.qml', 'utf8')
const manifest = JSON.parse(fs.readFileSync(root + '/shell/plugins/agents/manifest.json', 'utf8'))

// ---- the two styles
assert(/setting\("barIconStyle", "Robot"\)/.test(panelSource), 'agents falls back to the robot style without a stored setting')
assert(/visible: !root\.usageIconStyle/.test(panelSource), 'agents hides the robot button in usage style')
assert(/visible: root\.usageIconStyle/.test(panelSource), 'agents shows the chips in usage style')
assert(/component UsageChip/.test(panelSource) && /model: root\.providers/.test(panelSource), 'agents draws one chip per subscription')
assert(/barPercentText/.test(panelSource) && /bindingWindow\(p\)/.test(panelSource), 'agents chips show the tightest limit')
assert(/component AgentMark/.test(panelSource) && /iconCandidatesForProvider/.test(panelSource), 'agents chips reuse the mark fallback walk')

// ---- the right-click toggle
assert(/Qt\.RightButton\) toggleIconStyle\(\)/.test(panelSource), 'agents right click flips the icon style')
assert(/else toggle\(\)/.test(panelSource), 'agents left click still reveals the panel')

// ---- persistence
assert(/for \(var key in root\.settings\) if \(key !== "id"\) entry\[key\] = root\.settings\[key\]/.test(panelSource), 'agents carries the existing settings into the persisted entry')
assert(/entry\.barIconStyle = usageIconStyle \? "Robot" : "Usage"[\s\S]*root\.settings = entry[\s\S]*updateEntryInline/.test(panelSource), 'agents applies the flipped style locally and writes it to shell.json')

// ---- shipped defaults
const defaults = manifest.barWidget.defaults
assertEqual(defaults.barIconStyle, 'Robot', 'agents ships the robot style as the default')
const styleField = manifest.barWidget.schema.find(function(field) { return field.key === 'barIconStyle' })
assert(!!styleField, 'agents exposes the icon style in the settings schema')
assertEqual(styleField.type, 'enum', 'agents offers the icon style as a choice')
assertDeepEqual(styleField.options, ['Robot', 'Usage'], 'agents offers exactly the two styles')
assertEqual(styleField.defaultValue, defaults.barIconStyle, 'agents schema default matches the shipped default')
JS
