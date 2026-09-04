#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command node

plugin="$ROOT/shell/plugins/panels/plugin-workbench"

jq -e '
  .id == "omarchy.plugin-workbench"
  and .kinds == ["bar-widget"]
  and .entryPoints.barWidget == "BarWidget.qml"
  and .barWidget.defaultSection == "right"
' "$plugin/manifest.json" >/dev/null || fail "Workbench has a first-party bar widget manifest"
pass "Workbench has a first-party bar widget manifest"

ROOT="$ROOT" node <<'NODE'
const fs = require('fs')
const root = process.env.ROOT
const widget = fs.readFileSync(root + '/shell/plugins/panels/plugin-workbench/BarWidget.qml', 'utf8')
const panel = fs.readFileSync(root + '/shell/plugins/panels/plugin-workbench/Panel.qml', 'utf8')
const bindings = fs.readFileSync(root + '/default/hypr/bindings/utilities.lua', 'utf8')

function assert(condition, message) {
  if (!condition) {
    console.error(`not ok - ${message}`)
    process.exit(1)
  }
  console.log(`ok - ${message}`)
}

assert(/moduleName: "omarchy\.plugin-workbench"/.test(widget), 'Workbench widget owns the first-party IPC target')
assert(/helperPath: "\/usr\/bin\/omarchy-plugin-workbench"/.test(widget), 'Workbench uses the packaged helper')
assert(/moduleName: "omarchy\.plugin-workbench"/.test(panel), 'Workbench panel matches the widget IPC target')
assert(/Qt\.Key_Down/.test(panel) && /Qt\.Key_Up/.test(panel), 'Workbench feed supports arrow-key scrolling')
assert(/Qt\.Key_PageDown/.test(panel) && /Qt\.Key_PageUp/.test(panel), 'Workbench feed supports page-key scrolling')
assert(/Qt\.Key_4/.test(panel) && /root\.setViewMode\("build"\)/.test(panel), 'Workbench exposes Build as its fourth workspace')
assert(/title: "1  DISCOVER"/.test(panel) && /title: "2  INSTALLED"/.test(panel) && /title: "3  UPDATES"/.test(panel) && /title: "4  BUILD"/.test(panel), 'Workbench keeps the four plugin workflows explicit')
assert(!/selectFlavor|discoveryFlavor/.test(panel), 'Workbench stays focused on plugins')
assert(/reuseItems: true/.test(panel) && /cacheBuffer: height/.test(panel), 'Workbench virtualizes its scrolling feeds')
assert(
  /o\.bind\("SUPER \+ ALT \+ P", "Plugin Workbench", "omarchy-shell shell toggle omarchy\.plugin-workbench"\)/.test(bindings),
  'Super Alt P opens Workbench through the shell'
)
NODE

jq -e '
  [.bar.layout.right[] | .id // .] as $ids |
  ($ids | index("omarchy.agents")) as $agents |
  ($ids | index("omarchy.plugin-workbench")) == $agents + 1
' "$ROOT/config/omarchy/shell.json" >/dev/null || fail "default bar places Workbench after agents"
pass "default bar places Workbench after agents"

grep -Fxq 'omarchy-plugin-workbench' "$ROOT/install/omarchy-base.packages" ||
  fail "fresh installs include the Workbench helper package"
pass "fresh installs include the Workbench helper package"
