#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command node

plugin="$ROOT/shell/plugins/panels/discovery"

jq -e '
  .id == "omarchy.discovery"
  and .kinds == ["bar-widget"]
  and .entryPoints.barWidget == "BarWidget.qml"
  and .barWidget.defaultSection == "right"
' "$plugin/manifest.json" >/dev/null || fail "Discovery has a first-party bar widget manifest"
pass "Discovery has a first-party bar widget manifest"

ROOT="$ROOT" node <<'NODE'
const fs = require('fs')
const root = process.env.ROOT
const widget = fs.readFileSync(root + '/shell/plugins/panels/discovery/BarWidget.qml', 'utf8')
const panel = fs.readFileSync(root + '/shell/plugins/panels/discovery/Panel.qml', 'utf8')
const bindings = fs.readFileSync(root + '/default/hypr/bindings/utilities.lua', 'utf8')

function assert(condition, message) {
  if (!condition) {
    console.error(`not ok - ${message}`)
    process.exit(1)
  }
  console.log(`ok - ${message}`)
}

assert(/moduleName: "omarchy\.discovery"/.test(widget), 'Discovery widget owns the first-party IPC target')
assert(/helperPath: "\/usr\/bin\/omarchy-discovery"/.test(widget), 'Discovery uses the packaged helper')
assert(/moduleName: "omarchy\.discovery"/.test(panel), 'Discovery panel matches the widget IPC target')
assert(/Qt\.Key_Down/.test(panel) && /Qt\.Key_Up/.test(panel), 'Discovery feeds support arrow-key scrolling')
assert(/Qt\.Key_PageDown/.test(panel) && /Qt\.Key_PageUp/.test(panel), 'Discovery feeds support page-key scrolling')
assert(/Qt\.Key_4/.test(panel) && /root\.setViewMode\("build"\)/.test(panel), 'Discovery exposes Build as its fourth workspace')
assert(/root\.selectFlavor\("app"\)/.test(panel) && /root\.selectFlavor\("plugin"\)/.test(panel) && /root\.selectFlavor\("theme"\)/.test(panel), 'Discovery treats apps, plugins, and themes as flavours')
assert(
  /o\.bind\("SUPER \+ ALT \+ D", "Discovery", "omarchy-shell shell toggle omarchy\.discovery"\)/.test(bindings),
  'Super Alt D opens Discovery through the shell'
)
NODE

jq -e '
  [.bar.layout.right[] | .id // .] as $ids |
  ($ids | index("omarchy.agents")) as $agents |
  ($ids | index("omarchy.discovery")) == $agents + 1
' "$ROOT/config/omarchy/shell.json" >/dev/null || fail "default bar places Discovery after agents"
pass "default bar places Discovery after agents"

grep -Fxq 'omarchy-discovery' "$ROOT/install/omarchy-base.packages" ||
  fail "fresh installs include the Discovery helper package"
pass "fresh installs include the Discovery helper package"
