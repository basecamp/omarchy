#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

bar="$ROOT/shell/plugins/bar/Bar.qml"
tray="$ROOT/shell/plugins/bar/widgets/Tray.qml"
widget_button="$ROOT/shell/Ui/WidgetButton.qml"

# The bar does not let a widget's own MouseArea see clicks: a slot-wide area
# takes the press so a drag can reorder the bar, then hands the click to
# whichever registered target sits under the cursor. These two lines are the
# contract every clickable bar surface has to satisfy — pin them, so a widget
# that stops meeting it fails here rather than by silently swallowing clicks.
grep -q 'typeof target.triggerPress === "function"' "$bar" ||
  fail "the bar selects click targets by their triggerPress function"
grep -q 'if (!root.pressModuleClickTarget(slot, mouse.button, mouse.x, mouse.y)) mouse.accepted = false' "$bar" ||
  fail "the bar refuses a click no registered target claims"
pass "the bar dispatches clicks through registered click targets"

# WidgetButton is where every other widget picks the contract up for free.
grep -q 'function triggerPress' "$widget_button" ||
  fail "WidgetButton exposes triggerPress"
grep -q 'registeredBar.registerClickTarget(root)' "$widget_button" ||
  fail "WidgetButton registers itself as a click target"
pass "WidgetButton meets the click-target contract"

# Tray icons are not WidgetButtons, so they have to meet it themselves. Without
# this a left click on a tray icon is refused and falls through to the bar's
# gesture area, where a double click toggles the bar's transparency.
grep -q 'function triggerPress' "$tray" ||
  fail "tray icons expose triggerPress" "a tray icon that cannot be pressed is not a click target"
grep -q 'registeredBar.registerClickTarget(trayItemRoot)' "$tray" ||
  fail "tray icons register as click targets"
grep -q 'registeredBar.unregisterClickTarget(trayItemRoot)' "$tray" ||
  fail "tray icons unregister their click target"
grep -q 'Component.onDestruction: if (registeredBar' "$tray" ||
  fail "tray icons drop their click target when destroyed"
pass "tray icons meet the click-target contract"

# A left click has to reach the item; the other buttons keep their old meaning.
trigger_body=$(awk '/function triggerPress\(button\)/,/^    \}/' "$tray")
grep -q 'modelData.activate()' <<<"$trigger_body" ||
  fail "a left click activates the tray item"
grep -q 'Qt.RightButton || trayItemRoot.modelData.onlyMenu' <<<"$trigger_body" ||
  fail "a right click, and a menu-only item, opens the tray menu"
grep -q 'Qt.MiddleButton' <<<"$trigger_body" ||
  fail "a middle click secondary-activates the tray item"
pass "each mouse button keeps its meaning through the bar's dispatch"

# Collapsed drawer icons are parked outside their clip rectangle but still hold
# geometry there, so they must not be selectable until the drawer is revealed.
grep -q 'readonly property bool interactive: !inDrawer || root.revealProgress > 0' "$tray" ||
  fail "drawer icons stay unclickable until the drawer is revealed"
(( $(grep -c 'TrayItem { inDrawer: true }' "$tray") == 2 )) ||
  fail "both drawer repeaters mark their icons as drawer icons" \
    "found $(grep -c 'TrayItem { inDrawer: true }' "$tray"), expected 2 (horizontal and vertical bars)"
grep -q 'target.interactive !== false' "$bar" ||
  fail "the bar honours a target's interactive flag when selecting it"
pass "drawer icons are only click targets once revealed"
