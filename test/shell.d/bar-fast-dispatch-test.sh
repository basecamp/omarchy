#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')

const workspacesSource = fs.readFileSync(root + '/shell/plugins/bar/widgets/Workspaces.qml', 'utf8')
const menuWidgetSource = fs.readFileSync(root + '/shell/plugins/menu/BarWidget.qml', 'utf8')
const micWidgetSource = fs.readFileSync(root + '/shell/plugins/bar/widgets/Microphone.qml', 'utf8')

// Workspaces should use Hyprland.dispatch directly instead of shelling out to hyprctl
assert(
  /function focusWorkspace\(id\) \{\s*Hyprland\.dispatch\("hl\.dsp\.focus\(\{ workspace = \\"" \+ id \+ "\\" \}\)"\)\s*\}/.test(workspacesSource),
  'workspaces widget focuses workspaces via direct Hyprland.dispatch'
)
assert(
  !/root\.bar\.run\("hyprctl dispatch/.test(workspacesSource),
  'workspaces widget does not spawn a shell or hyprctl process to focus workspaces'
)

// Menu button should toggle in-process via root.bar.shell.toggle when available
assert(
  /root\.bar\.shell\.toggle\("omarchy\.menu",\s*JSON\.stringify\(\{\s*menu:\s*"root"\s*\}\)\)/.test(menuWidgetSource),
  'menu bar widget toggles menu directly in-process via root.bar.shell'
)
assert(
  /root\.bar\.run\("omarchy-shell shell toggle omarchy\.menu/.test(menuWidgetSource),
  'menu bar widget retains fallback shell toggle when root.bar.shell is unavailable'
)

// Microphone widget middle click should toggle audio in-process via root.bar.shell.toggle when available
assert(
  /root\.bar\.shell\.toggle\("omarchy\.audio"\)/.test(micWidgetSource),
  'microphone widget toggles audio panel in-process via root.bar.shell'
)
assert(
  /root\.bar\.run\("omarchy-shell shell toggle omarchy\.audio"\)/.test(micWidgetSource),
  'microphone widget retains fallback shell toggle when root.bar.shell is unavailable'
)
JS
