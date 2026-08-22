#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The command fixture follows the runtime invariant and reads defaults through
# OMARCHY_PATH. Point it at this checkout rather than whichever install launched
# the test (or nothing at all on a non-Omarchy development machine).
export OMARCHY_PATH="$ROOT"

if perl -0ne 'exit(/drag\s*\.\s*target\s*:\s*[^;]*\bslot\b/s ? 0 : 1)' "$ROOT/shell/plugins/bar/Bar.qml"; then
  fail "bar module dragging must not mutate ModuleSlot positions"
fi
pass "bar module dragging leaves layout-managed slots in place"

if rg -q 'barMoveSettling|barMoveSettleTimer' "$ROOT/shell/plugins/bar/Bar.qml"; then
  fail "bar move outline must clear when the pointer is released"
fi
pass "bar move outline has no post-release settling state"

# A widget above the gesture area propagates its composed press-and-hold down
# without handing over the grab, so the resulting move gets neither a release
# nor a cancel and the ghost stays up for the session. Only the grabbing area
# reports pressed, which is what separates the two, so the guard has to stay
# ahead of the drag.
if ! perl -0ne 'exit(/onPressAndHold:\s*function[^{]*\{[^}]*?\bpressed\b[^}]*?\bstartDrag\b/s ? 0 : 1)' \
  "$ROOT/shell/plugins/bar/Bar.qml"; then
  fail "bar move ignores a press-and-hold the gesture area does not hold the press for"
fi
pass "bar move ignores a press-and-hold propagated from a widget above"

run_node_test <<'JS'
const fs = require('fs')
const bar = requireFromRoot('shell/plugins/bar/BarModel.js')
const barSource = fs.readFileSync(root + '/shell/plugins/bar/Bar.qml', 'utf8')
const shellSource = fs.readFileSync(root + '/shell/shell.qml', 'utf8')

assert(/function toggleBarTransparency\(\): string \{[\s\S]*?shell\.bar\.toggleTransparency\(\)/.test(shellSource), 'shell exposes the bar transparency toggle over IPC')

// put tolerates a placement target the bar does not carry, so the IPC call
// must reach the registry's put rather than route back through enable.
assert(
  /function putBarWidget\(id: string, placementJson: string\): string \{[\s\S]*?shell\.pluginRegistry\.putBarWidget\(/.test(shellSource),
  'putting a bar widget over IPC goes through the registry put'
)

// Hiding must not unmap the bar. An unmapped layer surface has to be rebuilt on
// every reveal, which measured ~150ms against ~20ms to tear it down; parking it
// past the screen edge keeps show and hide symmetric at ~12ms.
assert(
  /visible: !remapGuard\.remapping/.test(barSource),
  'bar stays mapped while hidden so revealing it does not rebuild the surface'
)
assert(
  /exclusionMode: root\.barHidden \? ExclusionMode\.Ignore : ExclusionMode\.Auto/.test(barSource),
  'a hidden bar reserves no space for itself'
)
for (const edge of ['top', 'bottom', 'left', 'right']) {
  assert(
    new RegExp(`${edge}: root\\.barHidden && root\\.position === "${edge}" \\? -root\\.barSize : 0`).test(barSource),
    `a hidden bar parks past the ${edge} edge`
  )
}

// The center section declares two arrangements and shows one; the hidden one
// must not build its modules or every center widget exists twice.
const moduleList = barSource.slice(barSource.indexOf('component ModuleList'), barSource.indexOf('component ModuleSlot'))
assert(
  /active: visible && entries\.length > 0/.test(moduleList),
  'bar builds only the module list it is showing'
)

// A center module is mounted twice — drawn copy plus zero-size placeholder —
// and the order they register in is not stable across a live reconfiguration,
// so panel routing has to pick the one that is actually on screen.
const drawn = { moduleName: 'omarchy.clock', visible: true, width: 28, height: 81 }
const placeholder = { moduleName: 'omarchy.clock', visible: false, width: 0, height: 0 }
assertEqual(bar.isDrawnSlot(drawn), true, 'bar recognises a drawn slot')
assertEqual(bar.isDrawnSlot(placeholder), false, 'bar recognises a layout placeholder')
assertEqual(bar.pickDrawnSlot([placeholder, drawn]), drawn, 'bar picks the drawn slot when the placeholder registers first')
assertEqual(bar.pickDrawnSlot([drawn, placeholder]), drawn, 'bar picks the drawn slot when it registers first')
assertEqual(bar.pickDrawnSlot([placeholder]), placeholder, 'bar falls back to the placeholder when nothing is drawn')
assertEqual(bar.pickDrawnSlot([]), null, 'bar reports no slot when there are none')
assertEqual(bar.pickDrawnSlot(null), null, 'bar tolerates a missing slot list')

// Revealing the indicators can slide a neighbouring widget under a stationary
// pointer; collapsing the peek on that un-hover re-opens it and stutters the
// bar, so the peek stays held while the pointer is anywhere on the bar.
const revealTimer = barSource.slice(barSource.indexOf('id: centerSectionRevealTimer'))
const revealTimerBody = revealTimer.slice(0, revealTimer.indexOf('\n  }'))
assert(
  /!root\.centerSectionHovered && !root\.barHovered/.test(revealTimerBody),
  'the indicator peek stays held while the pointer is anywhere on the bar'
)

// The timer runs on a delay, so it can fire for a pointer that has already come
// back. Letting it assign the held state outright would then reveal indicators
// from bar hover alone; it may only close what the center section opened.
assert(
  !/centerSectionRevealHeld = (?!false)/.test(revealTimerBody),
  'the delayed collapse can only close the peek, never open it'
)

// The whole-bar hover has to come from an ancestor of the sections. A sibling
// loses hover to whichever section the pointer moved onto, which is the very
// signal the peek must not collapse on.
const barLoader = barSource.slice(barSource.indexOf('sourceComponent: root.vertical ? verticalBar : horizontalBar'))
const barLoaderBody = barLoader.slice(0, barLoader.indexOf('\n    }'))
assert(
  /setBarHovered\(hovered\)/.test(barLoaderBody),
  'the whole-bar hover handler is a child of the bar loader, above both orientations'
)

// Unplugging a monitor tears its bar down mid-hover with no leave event, which
// would leave that surface counted forever and the peek stuck open.
assert(
  /Component\.onDestruction: if \(hovered\) root\.setBarHovered\(false\)/.test(barLoaderBody),
  'a bar torn down while hovered gives its hover back'
)

// The helper has to record the state it is handed and re-run the collapse once
// the pointer leaves. It counts rather than assigns because every monitor's bar
// reports here: a slide from one bar to the next can deliver the enter before
// the leave, and a shared bool would read as un-hovered under a live pointer.
const setBarHovered = barSource.slice(barSource.indexOf('function setBarHovered'))
const setBarHoveredBody = setBarHovered.slice(0, setBarHovered.indexOf('\n  }'))
assert(
  /barHoverCount = Math\.max\(0, barHoverCount \+ \(hovered \? 1 : -1\)\)/.test(setBarHoveredBody),
  'each bar surface adds to a hover tally instead of overwriting a shared flag'
)
assert(
  /if \(barHoverCount === 0\) centerSectionRevealTimer\.restart\(\)/.test(setBarHoveredBody),
  'the peek collapse re-runs once the pointer has left the last bar'
)

// Opening the peek stays the center section's own gesture: pointing straight at
// a widget reveals nothing. Checking that only inside setBarHovered proves
// nothing, since the shared reveal timer is the path a bar hover leaks through.
const opensPeek = barSource.split('\n').filter(line => /centerSectionRevealHeld = true/.test(line))
assertEqual(opensPeek.length, 1, 'exactly one line in the bar opens the indicator peek')
const setCenterSectionHovered = barSource.slice(barSource.indexOf('function setCenterSectionHovered'))
assert(
  setCenterSectionHovered.slice(0, setCenterSectionHovered.indexOf('\n  }')).includes(opensPeek[0].trim()),
  'hovering the bar never opens the peek on its own'
)

// A bar surface is built per monitor, so a panel hotkey has one live copy of
// the widget per screen to choose between.
const internal = { moduleName: 'omarchy.audio', visible: true, width: 28, height: 81 }
const external = { moduleName: 'omarchy.audio', visible: true, width: 28, height: 81 }
const row = (slot, screenName, opened) => ({ slot, screenName, opened: opened === true })
const copies = [row(internal, 'eDP-1'), row(external, 'DP-1')]
assertEqual(
  bar.pickPanelSlot(copies, 'DP-1'),
  external,
  'bar summons a panel on the focused monitor'
)
assertEqual(
  bar.pickPanelSlot(copies, 'eDP-1'),
  internal,
  'bar summons a panel on the focused monitor whichever one it is'
)
assertEqual(
  bar.pickPanelSlot(copies, 'HDMI-A-1'),
  internal,
  'bar falls back to any live copy when the focused monitor has no bar'
)
assertEqual(
  bar.pickPanelSlot(copies, ''),
  internal,
  'bar falls back to any live copy before Hyprland reports a focused monitor'
)
assertEqual(
  bar.pickPanelSlot([row(internal, 'eDP-1', true), row(external, 'DP-1')], 'DP-1'),
  internal,
  'bar hides the panel that is open rather than the focused monitor copy'
)
assertEqual(
  bar.pickPanelSlot(
    [row(placeholder, 'DP-1'), row(drawn, 'DP-1'), row(internal, 'eDP-1')],
    'DP-1'
  ),
  drawn,
  'bar still picks the drawn slot among the focused monitor copies'
)
assertEqual(bar.pickPanelSlot([], 'DP-1'), null, 'bar reports no panel slot when there are none')
assertEqual(bar.pickPanelSlot(null, 'DP-1'), null, 'bar tolerates a missing panel slot list')
assert(
  /BarModel\.pickPanelSlot\(candidates, focusedScreenName\(\)\)/.test(barSource),
  'bar routes panel hotkeys through the focused-monitor picker'
)
assert(
  /function focusedScreenName\(\) \{[\s\S]*?Hyprland\.focusedMonitor/.test(barSource),
  'bar reads the focused monitor from Hyprland'
)
assert(
  /var slots = panelNavigationSlots\(currentSlot\.region, slotWindow\(currentSlot\)\)/.test(barSource),
  'bar tabs between panels within one bar surface'
)

// A positional hotkey means "the third panel in this section", so it counts the
// panels the bar actually draws. Reusing the tab-order walk is what keeps the
// count honest: a widget with no panel and a hidden one are already passed over
// there, and reading the layout config a second time would count both.
assert(
  /function panelWidgetIdAt\(region, index\) \{[\s\S]*?panelNavigationSlots\(String\(region \|\| ""\), null\)/.test(barSource),
  'bar counts positional panels off the drawn tab order'
)
assert(
  /var slot = slots\[Math\.round\(Number\(index\)\) - 1\]/.test(barSource),
  'positional panels are one-based, and anything off the end lands on no slot'
)
assert(
  /function togglePanelAt\(section: string, index: string\): string \{[\s\S]*?shell\.bar\.panelWidgetIdAt\(section, index\)[\s\S]*?shell\.toggle\(id, "\{\}"\)/.test(shellSource),
  'shell toggles a bar panel by its position over IPC'
)

const clockSlot = { id: 'clock' }
const traySlot = { id: 'tray' }
const horizontalTargets = [
  { slot: clockSlot, x: 100, y: 0, width: 100, height: 26 },
  { slot: traySlot, x: 500, y: 0, width: 50, height: 26 }
]
assertDeepEqual(
  bar.nearestDropTarget(horizontalTargets, { x: 240, y: 13 }, false),
  { slot: clockSlot, after: true },
  'bar resolves free space beside a widget to its nearest insertion edge'
)
assertDeepEqual(
  bar.nearestDropTarget(horizontalTargets, { x: 460, y: 13 }, false),
  { slot: traySlot, after: false },
  'bar resolves free space before a widget to its nearest insertion edge'
)
assertDeepEqual(
  bar.nearestDropTarget(horizontalTargets, { x: 125, y: 13 }, false),
  { slot: clockSlot, after: false },
  'bar resolves the first half of a widget before it'
)
assertDeepEqual(
  bar.nearestDropTarget(horizontalTargets, { x: 175, y: 13 }, false),
  { slot: clockSlot, after: true },
  'bar resolves the second half of a widget after it'
)
assertDeepEqual(
  bar.nearestDropTarget([
    { slot: clockSlot, x: 0, y: 100, width: 26, height: 80 }
  ], { x: 13, y: 220 }, true),
  { slot: clockSlot, after: true },
  'vertical bars resolve free space along their vertical axis'
)
assertEqual(bar.nearestDropTarget([], { x: 10, y: 10 }, false), null, 'bar reports no insertion edge without targets')
assert(
  /contentItem\.mapFromItem\(null, scenePoint\.x, scenePoint\.y\)[\s\S]*?return null/.test(barSource),
  'bar rejects free-space drops after the pointer leaves the bar'
)
assert(
  /BarModel\.nearestDropTarget\(candidates, scenePoint, root\.vertical\)/.test(barSource),
  'bar uses nearest insertion targeting for widget and free-space drops'
)
assert(
  /component DragGhostPanel:[\s\S]*?readonly property var targetRect: root\.barDragTargetGeometry[\s\S]*?color: Color\.accent/.test(barSource),
  'bar draws the insertion marker above the bar in the drag overlay'
)

// The open-panel mark sits on the module's desktop-facing edge at every
// position: under a top bar, over a bottom one, inward from left and right.
const indicator = barSource.slice(barSource.indexOf('id: openPanelIndicator'), barSource.indexOf('id: openPanelIndicator') + 1600)
assert(
  /x: root\.vertical\s*\n\s*\? \(root\.position === "left" \? parent\.width - width - inset : inset\)/.test(indicator),
  'bar pins the open-panel mark to the desktop-facing edge on vertical bars'
)
assert(
  /root\.position === "top" \? parent\.height - height - inset : inset/.test(indicator),
  'bar pins the open-panel mark to the desktop-facing edge on horizontal bars'
)
assert(
  /key in activeItem/.test(barSource),
  'bar asks whether a widget declares an indicator hint before reading it'
)
assert(
  /width: root\.vertical \? Style\.space\(2\) : slot\.panelIndicatorExtent/.test(indicator) &&
  /height: root\.vertical \? slot\.panelIndicatorExtent : Style\.space\(2\)/.test(indicator),
  'bar sizes the open-panel mark from the same content hint on both axes'
)

assertEqual(bar.normalizePosition('left'), 'left', 'bar accepts valid positions')
assertEqual(bar.normalizePosition('sideways'), 'top', 'bar defaults invalid positions')
assertDeepEqual(bar.entrySettings({ id: 'omarchy.clock', format: 'HH:mm' }), { format: 'HH:mm' }, 'bar extracts entry settings')
assertEqual(bar.entryId({ id: 'omarchy.clock' }), 'omarchy.clock', 'bar extracts object entry ids')
assertEqual(bar.entryId('omarchy.clock'), 'omarchy.clock', 'bar extracts string entry ids')

const entries = [{ id: 'a' }, { id: 'omarchy.tray' }, { id: 'b' }]
assertDeepEqual(bar.pinTrayToInner(entries, 'left').map(bar.entryId), ['a', 'b', 'omarchy.tray'], 'bar pins tray to left inner edge')
assertDeepEqual(bar.pinTrayToInner(entries, 'right').map(bar.entryId), ['omarchy.tray', 'a', 'b'], 'bar pins tray to right inner edge')

// A settings-only shell.json write must patch the live bar, not rebuild it:
// the module Repeaters recreate every widget when their array model changes.
const settingsLayout = { left: [{ id: 'omarchy.power' }], center: [{ id: 'omarchy.clock', format: 'HH:mm' }], right: [] }
assertDeepEqual(
  bar.inlineSettingsDelta(settingsLayout, { left: [{ id: 'omarchy.power', showPercentage: true }], center: [{ id: 'omarchy.clock', format: 'HH:mm' }], right: [] }),
  [{ region: 'left', index: 0, entry: { id: 'omarchy.power', showPercentage: true } }],
  'bar reports a settings-only change as an inline delta'
)
assertDeepEqual(
  bar.inlineSettingsDelta(settingsLayout, JSON.parse(JSON.stringify(settingsLayout))),
  [],
  'bar reports an unchanged layout as an empty delta'
)
assertEqual(
  bar.inlineSettingsDelta(settingsLayout, { left: [{ id: 'omarchy.clock', format: 'HH:mm' }], center: [{ id: 'omarchy.power' }], right: [] }),
  null,
  'bar treats reordered entries as structural'
)
assertEqual(
  bar.inlineSettingsDelta(settingsLayout, { left: [{ id: 'omarchy.power' }, { id: 'omarchy.battery' }], center: settingsLayout.center, right: [] }),
  null,
  'bar treats added entries as structural'
)
assertEqual(
  bar.inlineSettingsDelta(
    { left: [{ id: 'local.status', exec: 'date' }], center: [], right: [] },
    { left: [{ id: 'local.status', exec: 'uptime' }], center: [], right: [] }
  ),
  null,
  'bar rebuilds for custom modules, which read their entry directly'
)
assertEqual(
  bar.inlineSettingsDelta(
    { left: [{ id: 'x' }], center: [], right: [{ id: 'x' }] },
    { left: [{ id: 'x', a: 1 }], center: [], right: [{ id: 'x' }] }
  ),
  null,
  'bar rebuilds when a changed id appears more than once in the layout'
)
assert(
  /BarModel\.inlineSettingsDelta\(layoutConfig, next\)/.test(barSource),
  'bar consults the inline settings delta before rebuilding the layout'
)

assertEqual(bar.moduleString({ id: 'custom', label: 42 }, 'label', 'fallback'), '42', 'bar stringifies module settings')
assertEqual(bar.entryIndex(entries, 'b'), 2, 'bar finds entry indexes')
assertDeepEqual(bar.entriesBefore(entries, 'b').map(bar.entryId), ['a', 'omarchy.tray'], 'bar returns entries before target')
assertDeepEqual(bar.entriesAfter(entries, 'a').map(bar.entryId), ['omarchy.tray', 'b'], 'bar returns entries after target')

assertEqual(bar.expandPath('~/module.qml', '/home/dhh'), '/home/dhh/module.qml', 'bar expands tilde paths')
assertEqual(bar.expandPath('$HOME/module.qml', '/home/dhh'), '/home/dhh/module.qml', 'bar expands HOME paths')
assert(bar.customModuleSafeName('local.weather'), 'bar accepts safe custom module names')
assert(!bar.customModuleSafeName('../escape'), 'bar rejects path traversal custom module names')
assertEqual(bar.customModuleType({ id: 'custom', exec: 'date' }), 'command', 'bar infers command custom modules')
assertEqual(bar.customModuleType({ id: 'custom', source: '~/Custom.qml' }), 'qml', 'bar infers qml custom modules')
assertEqual(
  bar.customModulePath({ id: 'local.weather' }, '/home/dhh', '/home/dhh/.config/omarchy'),
  '/home/dhh/.config/omarchy/bar/modules/local.weather.qml',
  'bar builds default custom module paths'
)
JS

put_tmp=$(mktemp -d)
trap 'rm -rf "$put_tmp"' EXIT
mkdir -p "$put_tmp/bin"
ln -s "$ROOT/bin/omarchy-shell-config" "$put_tmp/bin/omarchy-shell-config"

cat >"$put_tmp/bin/omarchy-shell" <<'STUB'
#!/bin/bash
case ${OMARCHY_TEST_SHELL_STATE:-ready} in
  missing)
    echo "omarchy-shell is not running" >&2
    exit 1
    ;;
  starting)
    echo "omarchy-shell is not ready" >&2
    exit 1
    ;;
  crashing)
    # Seen coming up, then gone.
    if [[ -e $OMARCHY_TEST_SHELL_MARKER ]]; then
      echo "omarchy-shell is not running" >&2
    else
      touch "$OMARCHY_TEST_SHELL_MARKER"
      echo "omarchy-shell is not ready" >&2
    fi
    exit 1
    ;;
  oldshell)
    # A shell from before put learned to fall back.
    if [[ $4 == *"after"* ]]; then
      echo "could not find target widget omarchy.clock"
    else
      echo "ok"
    fi
    exit 0
    ;;
  spawning)
    # Launched, but with no socket to answer on yet.
    if [[ ! -e $OMARCHY_TEST_SHELL_MARKER ]]; then
      touch "$OMARCHY_TEST_SHELL_MARKER"
      echo "omarchy-shell is not running" >&2
      exit 1
    fi
    ;;
  vanishing)
    # Answers the first ask, then is gone before the fallback lands.
    if [[ ! -e $OMARCHY_TEST_SHELL_MARKER ]]; then
      touch "$OMARCHY_TEST_SHELL_MARKER"
      echo "could not find target widget omarchy.clock"
      exit 0
    fi
    echo "omarchy-shell is not running" >&2
    exit 1
    ;;
  unsupported)
    # An older shell that predates this call.
    echo "Function not found." >&2
    exit 1
    ;;
  scanning)
    # Answering IPC, but has not read the plugins yet.
    if [[ ! -e $OMARCHY_TEST_SHELL_MARKER ]]; then
      touch "$OMARCHY_TEST_SHELL_MARKER"
      echo "not ready"
      exit 0
    fi
    ;;
esac
echo "ok"
STUB
chmod +x "$put_tmp/bin/omarchy-shell"

put_output=$(PATH="$put_tmp/bin:$ROOT/bin:$PATH" OMARCHY_TEST_SHELL_STATE=missing \
  OMARCHY_SHELL_ABSENT_ATTEMPTS=2 \
  "$ROOT/bin/omarchy-bar" put omarchy.keyboard-layout --after omarchy.clock 2>&1) ||
  fail "put carries on when no shell is running" "$put_output"
[[ $put_output == *"is not running"* ]] || fail "put says why it placed nothing" "$put_output"
pass "put carries on when no shell is running"

put_output=$(PATH="$put_tmp/bin:$ROOT/bin:$PATH" OMARCHY_TEST_SHELL_STATE=spawning \
  OMARCHY_TEST_SHELL_MARKER="$put_tmp/spawned" \
  "$ROOT/bin/omarchy-bar" put omarchy.keyboard-layout --after omarchy.clock 2>&1) ||
  fail "put waits for a shell that is being spawned" "$put_output"
[[ $put_output == "omarchy.keyboard-layout is on the bar" ]] || fail "put places once the shell answers" "$put_output"
pass "put waits for a shell that is being spawned"

put_output=$(PATH="$put_tmp/bin:$ROOT/bin:$PATH" OMARCHY_TEST_SHELL_STATE=starting OMARCHY_SHELL_READY_ATTEMPTS=2 \
  "$ROOT/bin/omarchy-bar" put omarchy.keyboard-layout --after omarchy.clock 2>&1) &&
  fail "put fails when the shell never becomes ready" "$put_output"
[[ $put_output == *"did not become ready"* ]] || fail "put says the shell never became ready" "$put_output"
pass "put fails when the shell never becomes ready"

put_output=$(PATH="$put_tmp/bin:$ROOT/bin:$PATH" OMARCHY_TEST_SHELL_STATE=crashing \
  OMARCHY_TEST_SHELL_MARKER="$put_tmp/started" \
  "$ROOT/bin/omarchy-bar" put omarchy.keyboard-layout --after omarchy.clock 2>&1) &&
  fail "put fails when a starting shell disappears" "$put_output"
[[ $put_output == *"did not become ready"* ]] || fail "put keeps a lost shell retryable" "$put_output"
pass "put fails when a starting shell disappears"

put_output=$(PATH="$put_tmp/bin:$ROOT/bin:$PATH" OMARCHY_TEST_SHELL_STATE=oldshell \
  "$ROOT/bin/omarchy-bar" put omarchy.keyboard-layout --after omarchy.clock 2>&1) ||
  fail "put falls back against a shell that has not restarted yet" "$put_output"
[[ $put_output == "omarchy.keyboard-layout is on the bar" ]] || fail "put places without the missing neighbour" "$put_output"
pass "put falls back against a shell that has not restarted yet"

put_output=$(PATH="$put_tmp/bin:$ROOT/bin:$PATH" OMARCHY_TEST_SHELL_STATE=vanishing \
  OMARCHY_TEST_SHELL_MARKER="$put_tmp/vanished" \
  "$ROOT/bin/omarchy-bar" put omarchy.keyboard-layout --after omarchy.clock 2>&1) &&
  fail "put fails when the shell goes away mid-fallback" "$put_output"
[[ $put_output == *"did not become ready"* ]] || fail "put remembers the shell answered once" "$put_output"
pass "put fails when the shell goes away mid-fallback"

put_output=$(PATH="$put_tmp/bin:$ROOT/bin:$PATH" OMARCHY_TEST_SHELL_STATE=unsupported \
  "$ROOT/bin/omarchy-bar" put omarchy.keyboard-layout --after omarchy.clock 2>&1) &&
  fail "put fails when the shell cannot answer the call" "$put_output"
[[ $put_output == *"Function not found"* ]] || fail "put passes on what the shell said" "$put_output"
pass "put fails when the shell cannot answer the call"

put_output=$(PATH="$put_tmp/bin:$ROOT/bin:$PATH" OMARCHY_TEST_SHELL_STATE=scanning \
  OMARCHY_TEST_SHELL_MARKER="$put_tmp/scanned" \
  "$ROOT/bin/omarchy-bar" put omarchy.keyboard-layout --after omarchy.clock 2>&1) ||
  fail "put asks again while the shell is still reading its plugins" "$put_output"
[[ $put_output == "omarchy.keyboard-layout is on the bar" ]] || fail "put places once the plugins are read" "$put_output"
pass "put asks again while the shell is still reading its plugins"

put_output=$(PATH="$put_tmp/bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-bar" put omarchy.keyboard-layout --after omarchy.clock 2>&1) ||
  fail "put places a widget through a ready shell" "$put_output"
[[ $put_output == "omarchy.keyboard-layout is on the bar" ]] || fail "put reports the placed widget" "$put_output"
pass "put places a widget through a ready shell"
