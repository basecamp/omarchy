#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

for plugin in ultimate-taskbar ultimate-start ultimate-run ultimate-settings ultimate-task-switcher; do
  manifest="$ROOT/shell/plugins/$plugin/manifest.json"
  [[ -f $manifest ]] || fail "plugin manifest exists: $plugin"
  jq -e '.schemaVersion == 1 and .id and .kinds and .entryPoints' "$manifest" >/dev/null \
    || fail "plugin manifest is valid JSON: $plugin"
  pass "plugin manifest is valid JSON: $plugin"
done

[[ ! -e $ROOT/shell/plugins/ultimate-window-chrome ]] \
  || fail "overlay caption plugin must not ship; compositor hyprbars is the Desktop Mode title bar"
pass "overlay caption plugin is gone"

jq -e '.id == "omarchy.ultimate-taskbar" and (.kinds | index("bar"))' \
  "$ROOT/shell/plugins/ultimate-taskbar/manifest.json" >/dev/null \
  || fail "taskbar plugin declares kind bar"
pass "taskbar plugin declares kind bar"

jq -e '.id == "omarchy.ultimate-start" and (.kinds | index("menu"))' \
  "$ROOT/shell/plugins/ultimate-start/manifest.json" >/dev/null \
  || fail "Start plugin declares kind menu"
pass "Start plugin declares kind menu"

[[ -f $ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml ]] || fail "Taskbar.qml exists"
[[ -f $ROOT/shell/plugins/ultimate-start/Start.qml ]] || fail "Start.qml exists"
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
if grep -Eq '^import QtQuick.Controls' "$ROOT/shell/Ui/SearchBox.qml"; then
  fail "SearchBox must not import QtQuick.Controls; that shadows qs.Ui.TextField with a white QQC field"
fi
pass "SearchBox uses the kit TextField"
if grep -B2 'tooltipText: "Lock"' "$ROOT/shell/plugins/ultimate-start/Start.qml" | grep -q '\\u23FB'; then
  fail "Lock must not reuse the shut-down power-symbol glyph"
fi
pass "Start lock glyph is distinct from shut down"
grep -Fq 'fillMode: Image.PreserveAspectFit' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start app icons scale into the row instead of painting at native SVG size"
grep -Fq 'Layout.preferredWidth: 20' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start app icons use layout preferred size so RowLayout cannot inherit a 512px implicitWidth"
grep -Fq 'clip: true' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start panel clips overflowing icon paints"
grep -Fq 'visibleEntries' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start unwraps AppSearch rows and hides developer tools from the idle list"
grep -Fq 'developerToolsInStart' "$ROOT/default/ultimate/profiles/desktop.json" \
  || fail "desktop profile declares developerToolsInStart"
grep -Fq '"name": "Chrome"' "$ROOT/default/ultimate/taskbar-pins.json" \
  || fail "shipped Desktop Mode pins include Chrome"
grep -Fq '"name": "Files"' "$ROOT/default/ultimate/taskbar-pins.json" \
  || fail "shipped Desktop Mode pins include Files"
grep -Fq 'shippedPinsPath' "$ROOT/shell/services/WindowService.qml" \
  || fail "WindowService loads shipped pins when the user has none"
grep -Fq 'omarchy-task-switcher' "$ROOT/shell/plugins/ultimate-task-switcher/Switcher.qml" \
  || fail "task switcher uses a distinct layer namespace"
rg -q 'virtio-vga,xres=1920,yres=1080' "$ROOT/test/vm/vm-run.ps1" \
  || fail "Desktop Mode VM launcher pins virtio-vga to 1920x1080 so preferred is not 640x480@240"
rg -q 'gtk,zoom-to-fit=on' "$ROOT/test/vm/vm-run.ps1" \
  || fail "Desktop Mode VM launcher zoom-to-fits GTK to the guest framebuffer"
grep -Fq 'anchors { top: true; bottom: true; left: true; right: true }' \
  "$ROOT/shell/plugins/ultimate-task-switcher/Switcher.qml" \
  || fail "task switcher PanelWindow is anchored to screen edges so Hyprland maps it"
grep -Fq 'activateFromSwitcher' "$ROOT/shell/plugins/ultimate-task-switcher/Switcher.qml" \
  || fail "task switcher cards are clickable"
pass "taskbar, Start, and switcher entry points exist"

[[ -f $ROOT/default/hypr/bindings/desktop.lua ]] || fail "desktop bindings exist"
[[ -f $ROOT/default/hypr/desktop-windows.lua ]] || fail "desktop window rules exist"
grep -Fq 'resize_on_border = true' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "desktop windowing enables resize-on-border"
grep -Fq 'gaps_out = 0' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "desktop windowing zeros tiling gaps so snap fills the work area"
grep -Fq 'size = { 880, 560 }' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "desktop windowing opens overlapping floats, not leftover snap halves"
grep -Fq 'hyprbars' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "desktop windowing loads compositor hyprbars title bars"
grep -Fq 'omarchy-shell window minimize active' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "hyprbars minimize goes through WindowService"
grep -Fq 'load_omarchy_minimize' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "desktop windowing loads omarchy-minimize"
[[ -f $ROOT/default/hypr/plugins/omarchy-minimize/main.cpp ]] \
  || fail "omarchy-minimize plugin source exists"
grep -Fq 'setHidden' "$ROOT/default/hypr/plugins/omarchy-minimize/main.cpp" \
  || fail "omarchy-minimize calls CWindow::setHidden"
if grep -Fq 'special:minimized' "$ROOT/default/hypr/plugins/omarchy-minimize/main.cpp"; then
  fail "omarchy-minimize must not park on special:minimized"
fi
[[ -f $ROOT/default/hypr/plugins/hyprbars/main.cpp ]] \
  || fail "hyprbars plugin source exists"
grep -Fq 'install -Dm755' "$ROOT/default/hypr/plugins/hyprbars/Makefile" \
  || fail "hyprbars Makefile installs into /usr/lib/hyprland-plugins"
[[ -f $ROOT/bin/omarchy-apply-hyprland-plugins ]] \
  || fail "omarchy-apply-hyprland-plugins builds compositor plugins"
grep -Fq '/usr/lib/hyprland-plugins' "$ROOT/bin/omarchy-apply-hyprland-plugins" \
  || fail "plugin apply installs into /usr/lib/hyprland-plugins"
grep -Fq 'omarchy-apply-hyprland-plugins' "$ROOT/install/config/hyprland-plugins.sh" \
  || fail "system setup compiles Desktop Mode Hyprland plugins"
if grep -Fq 'hyprland-plugin-hyprbars' "$ROOT/install/omarchy-other.packages"; then
  fail "hyprbars is not the AUR package name; Desktop Mode builds it into /usr/lib"
fi
if grep -Fq 'hyprpm' "$ROOT/default/hypr/desktop-windows.lua"; then
  fail "desktop windowing must not load hyprbars from hyprpm"
fi
if grep -Fq 'suppress_event = "maximize"' "$ROOT/default/hypr/desktop-windows.lua"; then
  fail "desktop windowing must not suppress maximize"
fi
if grep -Fq 'mon.width' "$ROOT/shell/services/WindowService.qml"; then
  fail "WindowService must not mix Quickshell monitor width into snap geometry"
fi
if grep -Fq 'mon.height' "$ROOT/shell/services/WindowService.qml"; then
  fail "WindowService must not mix Quickshell monitor height into snap geometry"
fi
grep -Fq 'WindowModel.compositorMonitor' "$ROOT/shell/services/WindowService.qml" \
  || fail "snap geometry comes from compositor monitor JSON"
grep -Fq 'function restoreNormal' "$ROOT/shell/services/WindowService.qml" \
  || fail "WindowService can restore the pre-snap rectangle"
grep -Fq 'restoreOrMinimize' "$ROOT/default/hypr/bindings/desktop.lua" \
  || fail "Win+Down restores or minimizes"
pass "desktop Hyprland path floats windows, uses hyprbars, and allows maximize"

[[ -f $ROOT/test/vm/vm-run.ps1 ]] || fail "portable VM helper exists"
grep -Fq 'qemu-system-x86_64' "$ROOT/test/vm/vm-run.ps1" || fail "VM helper launches QEMU"
pass "portable vm-run.ps1 helper exists"

[[ -f $ROOT/test/acceptance.d/hyprbars-pointer-proof.py ]] \
  || fail "acceptance helper proves hyprbars with an absolute pointer"
grep -Fq '/dev/uinput is missing' "$ROOT/test/acceptance.d/hyprbars-pointer-proof.py" \
  || fail "pointer proof fails when uinput is missing instead of skipping"
grep -Fq 'relative ydotool is not this gate' "$ROOT/test/acceptance.d/windows-native-test.sh" \
  || fail "windows-native harness must not skip-pass the mouse gate"
grep -Fq 'hyprbars-pointer-proof.py' "$ROOT/test/acceptance.d/windows-native-test.sh" \
  || fail "windows-native harness runs the absolute pointer proof"
if grep -A8 '"use Alt+Tab")' "$ROOT/test/acceptance.d/windows-native-test.sh" | grep -Fq commitCycle; then
  fail "Alt+Tab harness must not treat commitCycle as the mouse proof"
fi
grep -Fq 'activateFromSwitcher' "$ROOT/shell/plugins/ultimate-task-switcher/Switcher.qml" \
  || fail "task switcher cards call activateFromSwitcher"
grep -Fq 'cancelCycle' "$ROOT/shell/plugins/ultimate-task-switcher/Switcher.qml" \
  || fail "closing the switcher cancels a leftover Alt+Tab cycle"
pass "mouse proof helper fails honestly without an absolute pointer"

