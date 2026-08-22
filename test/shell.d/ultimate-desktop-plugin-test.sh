#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

for plugin in ultimate-taskbar ultimate-start ultimate-run ultimate-settings ultimate-task-switcher ultimate-window-chrome; do
  manifest="$ROOT/shell/plugins/$plugin/manifest.json"
  [[ -f $manifest ]] || fail "plugin manifest exists: $plugin"
  jq -e '.schemaVersion == 1 and .id and .kinds and .entryPoints' "$manifest" >/dev/null \
    || fail "plugin manifest is valid JSON: $plugin"
  pass "plugin manifest is valid JSON: $plugin"
done

jq -e '.id == "omarchy.ultimate-taskbar" and (.kinds | index("bar"))' \
  "$ROOT/shell/plugins/ultimate-taskbar/manifest.json" >/dev/null \
  || fail "taskbar plugin declares kind bar"
pass "taskbar plugin declares kind bar"

jq -e '.id == "omarchy.ultimate-start" and (.kinds | index("menu"))' \
  "$ROOT/shell/plugins/ultimate-start/manifest.json" >/dev/null \
  || fail "Start plugin declares kind menu"
pass "Start plugin declares kind menu"

jq -e '.id == "omarchy.ultimate-window-chrome" and (.kinds | index("overlay"))' \
  "$ROOT/shell/plugins/ultimate-window-chrome/manifest.json" >/dev/null \
  || fail "window chrome plugin declares kind overlay"
pass "window chrome plugin declares kind overlay"

[[ -f $ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml ]] || fail "Taskbar.qml exists"
[[ -f $ROOT/shell/plugins/ultimate-start/Start.qml ]] || fail "Start.qml exists"
[[ -f $ROOT/shell/plugins/ultimate-window-chrome/Chrome.qml ]] || fail "Chrome.qml exists"
grep -Fq 'omarchy-taskbar' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "taskbar uses a distinct layer namespace"
grep -Fq 'exclusiveZone:' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "taskbar sets an explicit exclusive zone so snap reads a bottom inset"
grep -Fq 'omarchy.ultimate-start' "$ROOT/shell/plugins/ultimate-taskbar/StartButton.qml" \
  || fail "Start button toggles the Start plugin"
if grep -Fq $'\u2630' "$ROOT/shell/plugins/ultimate-taskbar/StartButton.qml"; then
  fail "Start button must not be a hamburger"
fi
grep -Fq 'Start' "$ROOT/shell/plugins/ultimate-taskbar/StartButton.qml" \
  || fail "Start button is labeled Start"
grep -Fq 'Power User Mode' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start footer exposes the mode toggle"
grep -Fq 'omarchy-task-switcher' "$ROOT/shell/plugins/ultimate-task-switcher/Switcher.qml" \
  || fail "task switcher uses a distinct layer namespace"
grep -Fq 'anchors { top: true; bottom: true; left: true; right: true }' \
  "$ROOT/shell/plugins/ultimate-task-switcher/Switcher.qml" \
  || fail "task switcher PanelWindow is anchored to screen edges so Hyprland maps it"
grep -Fq 'activateFromSwitcher' "$ROOT/shell/plugins/ultimate-task-switcher/Switcher.qml" \
  || fail "task switcher cards are clickable"
grep -Fq 'omarchy-window-chrome' "$ROOT/shell/plugins/ultimate-window-chrome/Chrome.qml" \
  || fail "window chrome uses a distinct layer namespace"
grep -Fq 'toggleMaximize' "$ROOT/shell/plugins/ultimate-window-chrome/Chrome.qml" \
  || fail "caption double-click maximizes"
grep -Fq 'moveTo' "$ROOT/shell/plugins/ultimate-window-chrome/Chrome.qml" \
  || fail "caption drag moves through WindowService"
pass "taskbar, Start, switcher, and caption chrome entry points exist"

[[ -f $ROOT/default/hypr/bindings/desktop.lua ]] || fail "desktop bindings exist"
[[ -f $ROOT/default/hypr/desktop-windows.lua ]] || fail "desktop window rules exist"
grep -Fq 'resize_on_border = true' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "desktop windowing enables resize-on-border"
if grep -Fq 'suppress_event = "maximize"' "$ROOT/default/hypr/desktop-windows.lua"; then
  fail "desktop windowing must not suppress maximize"
fi
grep -Fq 'restoreOrMinimize' "$ROOT/default/hypr/bindings/desktop.lua" \
  || fail "Win+Down restores or minimizes"
pass "desktop Hyprland path floats windows and allows maximize"

[[ -f $ROOT/test/vm/vm-run.ps1 ]] || fail "portable VM helper exists"
grep -Fq 'qemu-system-x86_64' "$ROOT/test/vm/vm-run.ps1" || fail "VM helper launches QEMU"
pass "portable vm-run.ps1 helper exists"
