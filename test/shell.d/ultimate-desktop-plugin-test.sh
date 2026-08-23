#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

for plugin in ultimate-taskbar ultimate-start ultimate-run ultimate-settings ultimate-task-switcher ultimate-snap-chooser; do
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
grep -Fq 'initialScanDone' "$ROOT/shell/services/PluginRegistry.qml" \
  || fail "plugin registry records the first scan so Desktop Mode can wait for the taskbar"
grep -Fq 'if (!shell.pluginRegistry.initialScanDone) return ""' "$ROOT/shell/shell.qml" \
  || fail "shell does not mount omarchy.bar before the plugin scan, which crashes PopupAnchor on the bar switch"
grep -Fq 'shell.activeBarId !== ""' "$ROOT/shell/shell.qml" \
  || fail "plugin bar loader stays idle until a bar id is chosen"
grep -Fq 'hostWindow: barWindow' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "taskbar peek/menu popups anchor to the PanelWindow, not QsWindow.window"
grep -Fq 'anchor.window: root.hostWindow' "$ROOT/shell/plugins/ultimate-taskbar/TaskButton.qml" \
  || fail "TaskButton PopupWindow anchors to the taskbar PanelWindow"
if grep -Fq 'QsWindow' "$ROOT/shell/plugins/ultimate-taskbar/TaskButton.qml"; then
  fail "TaskButton must not bind PopupAnchor to QsWindow.window during PanelWindow complete"
fi
pass "Desktop Mode does not flash omarchy.bar or bind taskbar popups to a half-created window"
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
grep -Fq 'omarchy-shell window minimize 0x{:x}' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "hyprbars minimize goes through WindowService with the bar's address"
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
grep -Fq 'snapArrow' "$ROOT/default/hypr/bindings/desktop.lua" \
  || fail "Win+Arrow cycles halves then quarters through snapArrow"
grep -Fq 'snapChooser' "$ROOT/default/hypr/bindings/desktop.lua" \
  || fail "Win+Z summons the snap layout chooser"
grep -Fq 'omarchy-shell window snapChooser 0x{:x}' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "hyprbars has a maximize-adjacent snap layout button"
grep -Fq 'aeroDragEnd 0x{:x} {} {}' "$ROOT/default/hypr/plugins/hyprbars/barDeco.cpp" \
  || fail "hyprbars drag end sends cursor coordinates to aeroDragEnd"
grep -Fq 'formatWindowCmd' "$ROOT/default/hypr/plugins/hyprbars/barDeco.cpp" \
  || fail "hyprbars caption buttons format the owner address into the action"
if grep -Fq 'closeActive' "$ROOT/default/hypr/desktop-windows.lua"; then
  fail "hyprbars caption buttons must not call closeActive"
fi
if grep -Fq 'toggleMaximize active' "$ROOT/default/hypr/desktop-windows.lua"; then
  fail "hyprbars caption buttons must not target the focused window"
fi
if grep -Fq '{ tag = "chromium-based-browser" }' "$ROOT/default/hypr/desktop-windows.lua"; then
  fail "hyprbars:no_bar must not depend on the chromium-based-browser tag YouTube/Zoom drop"
fi
grep -Fq 'youtube' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "YouTube PWAs keep hyprbars:no_bar after dropping the chromium tag"
grep -Fq 'omarchy-shell window close 0x{:x}' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "hyprbars close names the bar's window address"
grep -Fq '^zen$' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "Zen browser no_bar is anchored so zenity keeps hyprbars"
if grep -Fq '|zen|' "$ROOT/default/hypr/desktop-windows.lua"; then
  fail "unanchored zen in desktop-windows would no_bar zenity"
fi
if grep -Fq '|zen|' "$ROOT/default/hypr/apps/browser.lua"; then
  fail "unanchored zen in browser.lua would tag zenity as Firefox"
fi
grep -Fq 'hyprbarsSnapInset' "$ROOT/test/acceptance.d/windows-native-test.sh" \
  || fail "toolkit snap proof uses WindowModel inset, not a hard-coded Chromium +32"
grep -Fq 'm_bDraggingThis || inputIsValid()' "$ROOT/default/hypr/plugins/hyprbars/barDeco.cpp" \
  || fail "hyprbars drag end still fires when the pointer is off the title bar"
grep -Fq 'windows[(activeIndex + 1)' "$ROOT/shell/plugins/ultimate-taskbar/TaskButton.qml" \
  || fail "grouped taskbar click cycles windows"
grep -Fq 'modelData.minimized' "$ROOT/shell/plugins/ultimate-taskbar/TaskButton.qml" \
  || fail "taskbar peek lists each window including minimized"
grep -Fq 'function saveLayout' "$ROOT/shell/plugins/ultimate-snap-chooser/Chooser.qml" \
  || fail "snap chooser can save the current layout"
grep -Fq 'omarchy.ultimate-task-switcher' "$ROOT/shell/plugins/ultimate-taskbar/TaskView.qml" \
  || fail "taskbar has a mouse Task View button"
grep -Fq 'taskView' "$ROOT/default/hypr/bindings/desktop.lua" \
  || fail "Win+Tab summons Task View"
grep -Fq 'createDesktop' "$ROOT/default/hypr/bindings/desktop.lua" \
  || fail "Win+Ctrl+D creates a desktop"
grep -Fq 'toggleFullscreen' "$ROOT/default/hypr/bindings/desktop.lua" \
  || fail "F11 toggles true fullscreen"
grep -Fq 'modal = true' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "xdg modal dialogs stay centered with the parent"
grep -Fq 'window_w' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "modal dialogs keep the size they asked for instead of 880x560"
grep -Fq 'chromeGlow' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "taskbar pins a Windows 7 Superbar glow instead of the theme accent"
if grep -Fq 'Tokens.accent.primary' "$ROOT/shell/plugins/ultimate-taskbar/TaskButton.qml"; then
  fail "taskbar buttons must not use the theme accent as the running indicator"
fi
if grep -Fq 'Tokens.accent.primary' "$ROOT/shell/plugins/ultimate-taskbar/StartButton.qml"; then
  fail "Start must not use the theme accent for the orb"
fi
if grep -Fq 'Tokens.surface.glass' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml"; then
  fail "taskbar must not fill with theme glass (Tokyo Night blue)"
fi
if grep -Fq 'disable-features=WaylandWindowDecorations' "$ROOT/config/chromium-flags.conf"; then
  fail "Chromium must keep Wayland CSD so hyprbars is not a second title bar"
fi
grep -Fq 'WaylandWindowDecorations' "$ROOT/config/chromium-flags.conf" \
  || fail "Chromium must enable Wayland window decorations (fused tab/caption chrome)"
grep -Fq 'hyprbars:no_bar' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "Desktop Mode hides hyprbars on CSD browsers and Cursor"
grep -Fq '^[Cc]ursor$' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "Desktop Mode hides hyprbars on Cursor CSD"
jq -e '.features.taskView == true' "$ROOT/default/ultimate/profiles/desktop.json" >/dev/null \
  || fail "desktop profile enables Task View"
grep -Fq 'omarchy-snap-chooser' "$ROOT/shell/plugins/ultimate-snap-chooser/Chooser.qml" \
  || fail "snap chooser uses a distinct layer namespace"
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
if grep -Fq '/home/omarchy' "$ROOT/test/acceptance.d/hyprbars-pointer-proof.py"; then
  fail "pointer proof must not hardcode the QEMU guest home"
fi
grep -Fq 'SUDO_USER' "$ROOT/test/acceptance.d/hyprbars-pointer-proof.py" \
  || fail "pointer proof uses the live session user, not a hardcoded guest name"
grep -Fq 'hyprbars-pointer-proof.py' "$ROOT/test/acceptance.d/windows-native-test.sh" \
  || fail "windows-native harness runs the absolute pointer proof"
grep -Fq 'cycleSnapshot' "$ROOT/test/acceptance.d/hyprbars-pointer-proof.py" \
  || fail "pointer proof aims at the live highlighted Alt+Tab card, not a two-foot layout"
grep -Fq 'unfocused × closed the focused window' "$ROOT/test/acceptance.d/hyprbars-pointer-proof.py" \
  || fail "pointer proof clicks × on an unfocused hyprbars and keeps the focused foot"
grep -Fq 'commitCycle' "$ROOT/test/acceptance.d/windows-native-test.sh" \
  || fail "Alt+Tab harness proves address-change with commitCycle, not only overlay summon"
grep -Fq 'WlrKeyboardFocus.None' "$ROOT/shell/plugins/ultimate-task-switcher/Switcher.qml" \
  || fail "task switcher must not steal keyboard focus; unmap would restore the previous window"
grep -Fq 'pendingActivate' "$ROOT/shell/plugins/ultimate-task-switcher/Switcher.qml" \
  || fail "card pick activates after overlay hide so unmap cannot steal focus"
grep -Fq 'activateFromSwitcher' "$ROOT/shell/plugins/ultimate-task-switcher/Switcher.qml" \
  || fail "task switcher cards call activateFromSwitcher"
grep -Fq 'cancelCycle' "$ROOT/shell/plugins/ultimate-task-switcher/Switcher.qml" \
  || fail "closing the switcher cancels a leftover Alt+Tab cycle"
if grep -Fq 'Virtual-1' "$ROOT/test/acceptance.d/windows-native-test.sh"; then
  fail "windows-native harness must not hardcode the QEMU output name Virtual-1"
fi
grep -Fq 'hl.dsp.window.close' "$ROOT/test/acceptance.d/base-test.sh" \
  || fail "acceptance close_windows uses Hyprland 0.56 lua close, not classic dispatch"
grep -Fq 'hyprctl dispatch' "$ROOT/test/acceptance.d/base-test.sh" \
  || fail "acceptance close_windows dispatches the close object; hyprctl eval does not run it"
grep -Fq 'function close(address: string)' "$ROOT/shell/shell.qml" \
  || fail "window IPC exposes addressed close, not only closeActive"
[[ -f $ROOT/test/acceptance.d/gtk-parented-dialog.py ]] \
  || fail "acceptance helper maps a GTK parented MessageDialog"
grep -Fq 'transient_for=parent' "$ROOT/test/acceptance.d/gtk-parented-dialog.py" \
  || fail "GTK parented dialog is transient_for its parent"
grep -Fq 'modal=True' "$ROOT/test/acceptance.d/gtk-parented-dialog.py" \
  || fail "GTK parented dialog is modal"
[[ -f $ROOT/test/acceptance.d/qt-w0-window.qml ]] \
  || fail "acceptance helper maps a resizable Qt Quick window"
grep -Fq 'title: "W0-Qt"' "$ROOT/test/acceptance.d/qt-w0-window.qml" \
  || fail "Qt W0 helper is a named Window, not a size-locked kdialog"
grep -Fq 'qt-project' "$ROOT/test/acceptance.d/windows-native-test.sh" \
  || fail "Qt snap probe matches qml6's live Wayland app id"
if grep -Eq 'prove_toolkit .*kdialog' "$ROOT/test/acceptance.d/windows-native-test.sh"; then
  fail "Qt snap probe must not use kdialog; that window cannot take a half-tile"
fi
pass "mouse proof helper fails honestly without an absolute pointer"

