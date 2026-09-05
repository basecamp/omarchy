#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const source = fs.readFileSync(root + '/shell/plugins/bar/widgets/Workspaces.qml', 'utf8')

// The bar used to stop at 10 because SUPER+1..0 stops there. Hyprland does
// not, so a workspace reached by other means must still get a tile.
assert(
  /if \(id > 0 && ids\.indexOf\(id\) === -1\) ids\.push\(id\)/.test(source),
  'workspaces widget lists every positive workspace id, with no upper bound'
)
assert(!/id <= 10/.test(source), 'workspaces widget no longer caps ids at 10')

// "0" for 10 mirrors its key. It only reads that way while nothing follows.
assert(
  /modelData === 10 && root\.highestWorkspaceId <= 10\) \? "0" : String\(modelData\)/.test(source),
  'workspace 10 is written as "0" only while it ends the row'
)

// The focus dot replaces a numeral the keyboard already knows. Above 10 there
// is no key, so the number must stay visible on the focused tile.
assert(/readonly property bool keyed: modelData <= 10/.test(source), 'workspaces above 10 count as unkeyed')

// Arbitrarily high workspace ids must not paint over the next tile. The
// horizontal bar can grow with the rendered numeral; a vertical bar cannot,
// so it clips to its slot and exposes the complete number in a tooltip.
assert(
  /fixedWidth: root\.vertical \? root\.barSize : Math\.max\(Style\.space\(20\), labelWidth \+ scaledHorizontalMargin \* 2\)/.test(source),
  'horizontal workspace tiles grow to fit long ids'
)
assert(/clip: root\.vertical/.test(source), 'vertical workspace tiles clip labels to the bar width')
assert(
  /tooltipText: wsName !== "" \? numeral : \(root\.vertical && numeral\.length > 2 \? numeral : ""\)/.test(source),
  'vertical workspace tiles expose long ids in a tooltip'
)
JS

run_node_test <<'JS'
const fs = require('fs')
const source = fs.readFileSync(root + '/shell/plugins/bar/widgets/Workspaces.qml', 'utf8')

// Names ride on the widget's shell.json entry like any other widget setting,
// so the bar's in-place settings patch delivers a rename without a restart.
assert(/readonly property var names: root\.setting\("names", \{\}\)/.test(source), 'workspace names are read from the widget settings')

// The command enforces the length; the widget still cuts a hand-edited name
// so shell.json cannot widen the bar. Array.from counts Unicode code points,
// matching Bash's locale-aware limit without splitting surrogate pairs.
assert(/var characters = Array\.from\(value\)/.test(source), 'workspace names are measured as Unicode code points')
assert(
  /characters\.length > maxNameLength \? characters\.slice\(0, maxNameLength - 1\)\.join\(""\) \+ "\\u2026" : value/.test(source),
  'an over-long Unicode name is cut with an ellipsis between code points'
)

// A name must never disappear behind the focus dot. A named focused tile
// marks focus by colour while an unnamed, keyed tile keeps the original dot.
assert(/text: wsName !== "" \? wsName : \(focused && keyed \? "\\uDB85\\uDCFB" : numeral\)/.test(source), 'a name is shown in place of the numeral and the focus dot')
assert(/active: visibleOnMonitor && \(wsName !== "" \|\| !focused \|\| !keyed\)/.test(source), 'a named focused tile marks its focus by colour')

// A vertical bar has no room for words.
assert(/readonly property string wsName: root\.vertical \? "" : root\.nameFor\(modelData\)/.test(source), 'a vertical bar keeps the numbers')

// The bar hands the command its own widget id, so a cloned widget names the
// entry it is actually configured on.
assert(/"omarchy-hyprland-workspace-name " \+ args \+ " --widget " \+ Util\.shellQuote\(root\.moduleName\)/.test(source), 'the name command targets this widget\'s own entry')
assert(/if \(button === Qt\.RightButton\) root\.runNameCommand\("--prompt " \+ modelData\)/.test(source), 'right-click prompts for a name')
assert(/else if \(button === Qt\.MiddleButton\) root\.runNameCommand\("--clear " \+ modelData\)/.test(source), 'middle-click clears the name')
JS

run_node_test <<'JS'
const fs = require('fs')
const source = fs.readFileSync(root + '/shell/plugins/bar/widgets/Workspaces.qml', 'utf8')

assert(
  /readonly property bool visibleOnMonitor: workspace !== null && workspace\.active/.test(source),
  'every workspace visible on a monitor is marked active'
)
assert(
  /active: visibleOnMonitor && \(wsName !== "" \|\| !focused \|\| !keyed\)/.test(source),
  'visible workspaces use colour without replacing the original focus dot'
)
assert(
  /activeColor: focused \? \(root\.bar \? root\.bar\.urgent : Color\.urgent\) : Color\.accent/.test(source),
  'the focused workspace uses the urgent colour and other visible workspaces use the accent colour'
)
assert(
  /hl\.dsp\.focus\(\{ monitor = \\"" \+ root\.screenName \+ "\\" \}\)/.test(source),
  'a workspace click first focuses the monitor that owns the clicked bar'
)
assert(
  /hl\.dsp\.focus\(\{ workspace = \\"" \+ id \+ "\\", on_current_monitor = true \}\)/.test(source),
  'a workspace click opens the workspace on that monitor'
)
JS
