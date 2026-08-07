#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')

const pluginDir = path.join(root, 'shell/plugins/workspace-overview')
const manifest = JSON.parse(fs.readFileSync(path.join(pluginDir, 'manifest.json'), 'utf8'))
const overview = fs.readFileSync(path.join(pluginDir, 'WorkspaceOverview.qml'), 'utf8')
const card = fs.readFileSync(path.join(pluginDir, 'WorkspaceCard.qml'), 'utf8')
const preview = fs.readFileSync(path.join(pluginDir, 'WindowPreview.qml'), 'utf8')
const workspaces = fs.readFileSync(path.join(root, 'shell/plugins/bar/widgets/Workspaces.qml'), 'utf8')
const tilingBindings = fs.readFileSync(path.join(root, 'default/hypr/bindings/tiling.lua'), 'utf8')

function qmlFunction(source, name) {
  const marker = `function ${name}(`
  const functionStart = source.indexOf(marker)
  assert(functionStart >= 0, `workspace overview defines ${name}`)
  const argsStart = functionStart + marker.length
  const argsEnd = source.indexOf(')', argsStart)
  const bodyStart = source.indexOf('{', argsEnd)
  let depth = 1
  let cursor = bodyStart + 1
  while (cursor < source.length && depth > 0) {
    if (source[cursor] === '{') depth++
    else if (source[cursor] === '}') depth--
    cursor++
  }
  const args = source.slice(argsStart, argsEnd).split(',').map(value => value.trim()).filter(Boolean)
  const body = source.slice(bodyStart + 1, cursor - 1)
  return new Function(...args, body)
}

assertEqual(manifest.id, 'omarchy.workspace-overview', 'workspace overview uses the first-party plugin id')
assertDeepEqual(manifest.kinds, ['overlay'], 'workspace overview is an overlay plugin')
assert(manifest.keepLoaded === undefined, 'workspace overview unloads after it closes')
assert(
  manifest.entryPoints.overlay === 'WorkspaceOverview.qml'
    && /function open\(payloadJson\)/.test(overview)
    && /function close\(\)/.test(overview)
    && /function toggle\(\)/.test(overview),
  'workspace overview remains available through the standard shell plugin IPC lifecycle'
)

assert(
  /var ids = \[1, 2, 3, 4, 5\][\s\S]*id > 0 && id <= 10/.test(overview),
  'workspace overview follows the workspace bar model'
)
assert(
  /model: root\.toplevelModel/.test(card) && /workspace \? workspace\.toplevels : \[\]/.test(card),
  'workspace cards bind directly to native workspace toplevel models'
)
assert(
  /if \(workspace\) workspace\.activate\(\)/.test(overview)
    && /Qt\.callLater\(root\.dismiss\)/.test(overview),
  'workspace card activation uses the native workspace API before deferred dismissal'
)
assert(
  /MouseArea \{[\s\S]*onClicked: root\.workspaceActivated\(\)/.test(card)
    && /TapHandler[\s\S]*onTapped: root\.activated\(\)/.test(preview),
  'workspace and window clicks have separate pointer owners'
)
assert(
  /ScreencopyView[\s\S]*captureSource: root\.waylandToplevel[\s\S]*live: false/.test(preview),
  'window previews use one-shot native Wayland screencopy'
)
assert(
  /Hyprland\.dispatch\("hl\.dsp\.focus\(\{ window = \\"address:[\s\S]*root\.dismiss\(\)/.test(overview),
  'window selection uses canonical exact-address Hyprland focus and dismisses the overlay'
)
assert(
  /else if \(wayland\)[\s\S]*wayland\.activate\(\)/.test(overview),
  'window selection falls back to native Wayland activation when no address is mapped'
)
assert(
  /WlrLayershell\.layer: WlrLayer\.Overlay/.test(overview)
    && /WlrLayershell\.keyboardFocus: WlrKeyboardFocus\.Exclusive/.test(overview),
  'workspace overview uses the standard focused overlay surface pattern'
)
assert(
  /DropArea \{[\s\S]*keys: \["omarchy-window"\][\s\S]*root\.windowDropped\(drop\.source\.toplevel\)/.test(card),
  'every workspace card accepts native window-preview drags'
)
assert(
  /hl\.dsp\.window\.move\(\{ workspace = \\\"[\s\S]*window = \\\"address:[\s\S]*follow = false/.test(overview)
    && /movetoworkspacesilent/.test(overview),
  'window moves identify the exact address and use silent workspace semantics'
)
assert(
  /sourceId === workspaceId\) return false/.test(overview),
  'same-workspace window drops are ignored'
)

const normalizedAddress = qmlFunction(overview, 'normalizedAddress')
assertEqual(normalizedAddress(null), '', 'missing toplevel address cancels window movement')
assertEqual(normalizedAddress({ address: '' }), '', 'empty toplevel address cancels window movement')
assertEqual(normalizedAddress({ address: 'abc123' }), '0xabc123', 'toplevel addresses gain the canonical hexadecimal prefix')
assertEqual(normalizedAddress({ address: '0xabc123' }), '0xabc123', 'prefixed toplevel addresses remain unchanged')

const nextWorkspaceAfter = qmlFunction(overview, 'nextWorkspaceAfter')
assertEqual(nextWorkspaceAfter([1, 2, 3, 4, 5]), 6, 'initial workspace layout adds workspace 6')
assertEqual(nextWorkspaceAfter([1, 2, 3, 4, 5, 6]), 7, 'existing workspace 6 advances the add card to workspace 7')
assertEqual(nextWorkspaceAfter([1, 2, 3, 4, 5, 6, 7, 8, 9]), 10, 'workspace 9 advances the add card to workspace 10')
assertEqual(nextWorkspaceAfter([1, 2, 3, 4, 5, 10]), -1, 'workspace 10 suppresses the add card')

const cardIndexAfterMove = qmlFunction(overview, 'cardIndexAfterMove')
assertEqual(cardIndexAfterMove(0, 1, 0, 6, 3), 1, 'Right selects the next workspace card')
assertEqual(cardIndexAfterMove(1, 0, 1, 6, 3), 4, 'Down selects the workspace card below')
assertEqual(cardIndexAfterMove(4, 0, -1, 6, 3), 1, 'Up selects the workspace card above')
assertEqual(cardIndexAfterMove(3, -1, 0, 6, 3), 3, 'Left stops at the start of a grid row')
assertEqual(cardIndexAfterMove(5, 0, 1, 7, 3), 6, 'Down reaches the plus card in an incomplete row')
assert(
  /if \(nextWorkspaceId > 0\) ids\.push\(nextWorkspaceId\)/.test(overview),
  'the plus card follows the highest represented workspace in the responsive grid'
)
assert(
  /function activateNextWorkspace[\s\S]*dispatchWorkspace\(workspaceId\)[\s\S]*Qt\.callLater\(root\.dismiss\)/.test(overview),
  'plus click dispatches and activates the next workspace before closing'
)
const moveFunction = overview.slice(
  overview.indexOf('function moveWindowToWorkspace'),
  overview.indexOf('function beginWindowDrag')
)
assert(!/dismiss|activateWorkspace|dispatchWorkspace/.test(moveFunction), 'dragging a window does not activate a workspace or close the overview')
assert(
  /onWindowDropped: function\(toplevel\) \{ root\.moveWindowToWorkspace\(toplevel, modelData\) \}/.test(overview),
  'dropping onto plus reuses silent specific-window movement without workspace activation'
)
assert(
  /TapHandler[\s\S]*onTapped: root\.activated\(\)/.test(preview)
    && /DragHandler[\s\S]*dragThreshold: Style\.space\(6\)/.test(preview)
    && /dragProxy\.Drag\.drop\(\)[\s\S]*Drag\.active: dragSessionActive/.test(preview),
  'window dragging starts after a pointer threshold and suppresses click activation'
)
assert(/function activateWindow[\s\S]*root\.dismiss\(\)/.test(overview), 'normal window clicks still dismiss the overview')
assert(/PanelKeyCatcher[\s\S]*onCloseRequested: root\.dismiss\(\)/.test(overview), 'Escape still dismisses the overview')
assert(
  !/text: "Workspace Overview"/.test(overview),
  'workspace overview omits the visible heading'
)
assert(
  /PanelKeyCatcher[\s\S]*onMoveRequested:[\s\S]*moveCardSelection/.test(overview)
    && /onActivateRequested: root\.activateSelectedCard\(\)/.test(overview)
    && /keyboardSelected: index === root\.selectedCardIndex/.test(overview),
  'arrow keys select workspace cards and Enter activates the selection'
)
assert(
  /o\.bind\("ALT \+ TAB", "Focus on next window", hl\.dsp\.window\.cycle_next\(\)\)/.test(tilingBindings)
    && /o\.bind\("ALT \+ SHIFT \+ TAB", "Focus on previous window", hl\.dsp\.window\.cycle_next\(\{ next = false \}\)\)/.test(tilingBindings)
    && /o\.bind\("ALT \+ TAB", "Reveal active window on top", hl\.dsp\.window\.bring_to_top\(\)\)/.test(tilingBindings)
    && /o\.bind\("ALT \+ SHIFT \+ TAB", "Reveal active window on top", hl\.dsp\.window\.bring_to_top\(\)\)/.test(tilingBindings)
    && !/omarchy\.workspace-overview/.test(tilingBindings),
  'the original Alt+Tab bindings remain intact and do not open the workspace overview'
)
assert(
  /button === Qt\.RightButton[\s\S]*toggle\("omarchy\.workspace-overview"/.test(workspaces)
    && /button === Qt\.LeftButton[\s\S]*focusWorkspace\(modelData\)/.test(workspaces),
  'workspace buttons preserve left-click switching and add right-click overview toggling'
)
assert(!/hyprctl clients|hyprpm|hyprexpo/.test(overview + card + preview), 'workspace overview adds no client polling or external overview dependency')
JS
