#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const panelSource = fs.readFileSync(root + '/shell/plugins/agents/Panel.qml', 'utf8')
const mainSource = fs.readFileSync(root + '/shell/plugins/agents/Main.qml', 'utf8')
const accountSwitchSource = fs.readFileSync(root + '/bin/omarchy-agent-account-switch', 'utf8')
const accountBackendsSource = fs.readFileSync(root + '/bin/omarchy-agent-account-backends', 'utf8')
const manifest = JSON.parse(fs.readFileSync(root + '/shell/plugins/agents/manifest.json', 'utf8'))

assert(/function launchAgent\(\)/.test(panelSource), 'agents panel launches the default agent')
assert(/root\.bar\.run\("omarchy-agent --pick"\)/.test(panelSource), 'agents panel uses the desktop agent launcher')
assert(/if \(buttonCode === Qt\.RightButton\) root\.launchAgent\(\)/.test(panelSource), 'agents right click launches the agent')
assert(/else if \(buttonCode === Qt\.MiddleButton\) root\.selectProvider\(root\.providerIndex \+ 1\)/.test(panelSource), 'agents middle click still advances the subscription')
assert(/else root\.toggle\(\)/.test(panelSource), 'agents left click still toggles the panel')
assert(!/if \(buttonCode === Qt\.RightButton\) root\.refreshNow\(\)/.test(panelSource), 'agents right click no longer refreshes')
assert(panelSource.includes('omarchy agent account switch '), 'agents panel switches the selected subscription account explicitly')
assert(/t === "s" \|\| t === "S"/.test(panelSource), 'agents panel binds s to account switching')
assert(
  /agent_account_refresh_shell/.test(accountSwitchSource)
    && /omarchy-shell -q omarchy\.agents refresh/.test(accountBackendsSource),
  'account switching requests a panel refresh after the credential swap'
)
assert(panelSource.includes('p.providerName + " · " + p.accountLabel'), 'agents panel disambiguates multiple accounts from one provider')
assert(panelSource.includes('iconText: modelData.accountActive ? "✓" : ""'), 'agents panel marks the active account chip')
assert(panelSource.includes('Shared-harness tokens appear in the charts but never move these plan limits'), 'agents panel explains shared tokens beside the limits and charts')
assert(/if \(providerId === "anthropic"\) return "claude"/.test(panelSource), 'agents panel maps Anthropic records to the Claude asset')
assert(/if \(providerId === "openai"\) return "codex"/.test(panelSource), 'agents panel maps OpenAI records to the Codex asset')

assert(/advising\.push\(providerId\)/.test(mainSource), 'agents limits retry passes the provider accepted by the updater')
assert(/function providerEnabled\(id\)[\s\S]*legacyProviderId\(providerId\)/.test(mainSource), 'agents settings accept legacy Claude and Codex provider keys')
assert(mainSource.includes('providerAccountKey(providerId, accountId)'), 'agents sync keys records by provider and account identity')
assert(mainSource.includes('var identity = snapshotIdentity(providerKey, stats)'), 'agents sync reads provider and account identity from each snapshot record')
assertDeepEqual(
  Object.keys(manifest.barWidget.defaults.providers),
  ['anthropic', 'openai', 'fireworks'],
  'agents manifest defaults use canonical provider ids'
)
JS
