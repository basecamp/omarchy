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
grep -Fq 'implicitWidth: 440' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start maps a card-sized overlay, not a full-screen click sink"
grep -Fq 'anchors.left: true' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start card sits on the bottom-left above the Superbar"
grep -Fq 'margins.bottom: 48' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start card sits above the Superbar exclusive zone"
if grep -Fq 'anchors { top: true; bottom: true; left: true; right: true }' "$ROOT/shell/plugins/ultimate-start/Start.qml"; then
  fail "Start must not map a full-screen overlay that swallows outside clicks"
fi
if grep -Fq 'HyprlandFocusGrab {' "$ROOT/shell/plugins/ultimate-start/Start.qml"; then
  fail "HyprlandFocusGrab swallows the outside click; Start click-through cannot use it"
fi
grep -Fq 'onActiveToplevelChanged' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start closes when another window takes focus so the click already hit that window"
grep -Fq 'if (!next)' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start must not treat layer-shell keyboard focus as a window change"
if grep -Fq 'next !== root.focusedWhenOpened' "$ROOT/shell/plugins/ultimate-start/Start.qml"; then
  fail "Start must close when the previously focused window is clicked again"
fi
if grep -Fq 'WlrKeyboardFocus.Exclusive' "$ROOT/shell/plugins/ultimate-start/Start.qml"; then
  fail "Exclusive Start keyboard focus swallows wallpaper clicks"
fi
grep -Fq 'omarchy-start' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "Desktop Mode tracks the Start layer for click-through"
grep -Fq 'Dismiss Start click-through' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "Desktop Mode binds a pass-through click while Start is mapped"
grep -Fq 'non_consuming = true' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "Start click-through bind must be non_consuming so the orb and the window still get the click"
if grep -Fq 'o.bind("mouse:272"' "$ROOT/default/hypr/bindings/desktop.lua"; then
  fail "global left-click must not bind dismissOutside; that bind eats CSD min/max/close"
fi
grep -Fq 'TransientSurfaceCoordinator' "$ROOT/shell/shell.qml" \
  || fail "shell owns a shared transient coordinator"
grep -Fq 'transientCoordinator.dismiss' "$ROOT/shell/plugins/background/Background.qml" \
  || fail "empty-desktop clicks dismiss the active transient"
grep -Fq 'transientCoordinator.dismiss' "$ROOT/shell/plugins/ultimate-taskbar/TaskButton.qml" \
  || fail "Superbar activation dismisses Start without swallowing the click"
grep -Fq 'startWasOpen' "$ROOT/shell/plugins/ultimate-taskbar/TaskButton.qml" \
  || fail "clicking a Superbar icon while Start is open must not toggle-minimize the active window"
grep -Fq 'shell.hide("omarchy.ultimate-start")' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start hide stays in sync with the shell so Super and the orb can reopen"
grep -Fq 'Loader {' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "closed Start unmaps its overlay instead of leaving a click sink"
grep -Fq 'clicking a window under Start left omarchy-start mapped' \
  "$ROOT/test/acceptance.d/start-dismiss-proof.py" \
  || fail "Start dismiss proof includes click-through onto a window"
if grep -Fq 'o.bind("mouse:272"' "$ROOT/default/hypr/bindings/desktop.lua"; then
  fail "global left-click must not bind dismissOutside; that bind eats CSD min/max/close"
fi
if grep -Fq 'omarchy-shell shell dismissOutside' "$ROOT/default/hypr/bindings/desktop.lua"; then
  fail "desktop bindings must not exec dismissOutside on every left click"
fi
grep -Fq 'function dismissOutside' "$ROOT/shell/shell.qml" \
  || fail "shell IPC still exposes dismissOutside for wallpaper and tests"
grep -Fq 'activateAtCursorSoon' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start close re-activates the window under the cursor after unmap, without a global click bind"
grep -Fq 'raiseUnderCursorOnClose' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start only raises the clicked window when another toplevel took focus"
grep -Fq 'launchingFromStart' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start launch must not activateAtCursorSoon; that fights the new window"
grep -Fq 'setExempt("start"' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start card hover is exempt from outside-click dismiss"
grep -Fq 'setExempt("taskbar"' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "Superbar hover is exempt so the Start orb can toggle"
if grep -Fq 'scrim' "$ROOT/shell/plugins/ultimate-start/Start.qml"; then
  fail "Start must not dim the desktop when open"
fi
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
grep -Fq 'sourceSize.width: 48 * Screen.devicePixelRatio' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
  || fail "Start pinned tiles use 48px icons, not text-only chips"
grep -Fq 'Layout.preferredWidth: 32' "$ROOT/shell/plugins/ultimate-start/Start.qml" \
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
grep -Fq 'omarchy_desktop_floats = true' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "Desktop Mode must tell browser.lua not to tile Chromium"
floats_line=$(grep -n 'omarchy_desktop_floats = true' "$ROOT/default/hypr/desktop-windows.lua" | head -1 | cut -d: -f1)
apps_line=$(grep -n 'require("default.hypr.apps")' "$ROOT/default/hypr/desktop-windows.lua" | head -1 | cut -d: -f1)
(( floats_line < apps_line )) || fail "omarchy_desktop_floats must be set before default.hypr.apps tiles Chromium"
grep -Fq 'omarchy_desktop_floats' "$ROOT/default/hypr/apps/browser.lua" \
  || fail "browser.lua must not tile Chromium in Desktop Mode"
grep -Fq 'tile = true' "$ROOT/default/hypr/apps/browser.lua" \
  || fail "tiling mode must still tile Chromium"
grep -Fq 'omarchy_apply_desktop_look' "$ROOT/config/hypr/hyprland.lua" \
  || fail "Desktop Mode chrome must re-apply after user looknfeel or cyan borders win"
looknfeel_line=$(grep -n '^require("hypr.looknfeel")' "$ROOT/config/hypr/hyprland.lua" | head -1 | cut -d: -f1)
apply_look_line=$(grep -n 'omarchy_apply_desktop_look' "$ROOT/config/hypr/hyprland.lua" | head -1 | cut -d: -f1)
(( apply_look_line > looknfeel_line )) || fail "desktop look must run after hypr.looknfeel"
grep -Fq 'windowsIn", enabled = false' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "desktop mode must disable looknfeel popin so maximize is not jank"
grep -Fq 'no_shadow = true' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "CSD clients must not get a second compositor shadow"
grep -Fq 'resize_on_border = true' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "desktop windowing enables resize-on-border"
grep -Fq 'extend_border_grab_area = 4' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "desktop overlapping floats use a Windows-sized resize grab, not a 15px click sink"
grep -Fq 'follow_mouse = 0' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "Desktop Mode is click-to-focus; follow_mouse 1 leaves background windows behind"
grep -Fq 'gaps_out = 0' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "desktop windowing zeros tiling gaps so snap fills the work area"
grep -Fq 'size = { 880, 560 }' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "desktop windowing opens overlapping floats, not leftover snap halves"
grep -Fq 'size = { 1200, 740 }' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "CSD clients open wide enough that Chromium can draw min/max/close"
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
grep -Fq 'requestsMinimize' "$ROOT/default/hypr/plugins/omarchy-minimize/main.cpp" \
  || fail "omarchy-minimize honors xdg/X11 CSD minimize requests"
grep -Fq 'requestsMaximize' "$ROOT/default/hypr/plugins/omarchy-minimize/main.cpp" \
  || fail "omarchy-minimize honors xdg/X11 CSD maximize requests"
grep -Fq 'FSMODE_MAXIMIZED' "$ROOT/default/hypr/plugins/omarchy-minimize/main.cpp" \
  || fail "CSD maximize uses Hyprland maximized fullscreen, not omarchy-shell"
grep -Fq 'syncCsdMaximizedState' "$ROOT/default/hypr/plugins/omarchy-minimize/main.cpp" \
  || fail "CSD windows must drop Hyprland's fake map-time maximized state"
grep -Fq 'hyprbars:no_bar' "$ROOT/default/hypr/plugins/omarchy-minimize/main.cpp" \
  || fail "fake maximized is cleared only for hyprbars:no_bar CSD clients"
if grep -Fq 'omarchy-shell' "$ROOT/default/hypr/plugins/omarchy-minimize/main.cpp"; then
  fail "omarchy-minimize must not exec omarchy-shell from the compositor"
fi
grep -Fq 'sendWmCapabilities' "$ROOT/default/hypr/plugins/omarchy-minimize/main.cpp" \
  || fail "omarchy-minimize advertises xdg min/max so Chromium draws CSD buttons"
grep -Fq 'restoreCsdCaption' "$ROOT/default/hypr/plugins/omarchy-minimize/main.cpp" \
  || fail "CSD caption restore exists so Chrome keeps min/max/close on its own row"
grep -Fq 'scheduleConfigure' "$ROOT/default/hypr/plugins/omarchy-minimize/main.cpp" \
  || fail "wm_capabilities change must be followed by xdg_surface.configure"
grep -Fq 'XDG_TOPLEVEL_STATE_TILED_LEFT' "$ROOT/default/hypr/plugins/omarchy-minimize/main.cpp" \
  || fail "CSD configure must drop Hyprland fake tiled-on-all-sides or Chrome hides min/max"
grep -Fq 'ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE' "$ROOT/default/hypr/plugins/omarchy-minimize/main.cpp" \
  || fail "Hyprland SSD decoration replies must be overridden so Chrome draws min/max/close"
grep -Fq '[cC]hrom' "$ROOT/default/ultimate/csd-clients.json" \
  || fail "Chrome stays on the CSD list; hyprbars on Chrome is a second title bar"
grep -Fq 'm_events.window.open' "$ROOT/default/hypr/plugins/omarchy-minimize/main.cpp" \
  || fail "omarchy-minimize watches mapped windows for CSD minimize"
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
grep -Fq 'hover_action = "omarchy-shell window snapChooser 0x{:x}"' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "hyprbars maximize hover summons the snap layout chooser"
grep -Fq 'handleButtonHover' "$ROOT/default/hypr/plugins/hyprbars/barDeco.cpp" \
  || fail "hyprbars fires hover_action from the title-bar pointer path"
awk '
  $0 ~ /void CHyprBar::draw\(/ { infn = 1 }
  infn && /handleButtonHover\(\)/ { found = 1 }
  infn && /^void CHyprBar::/ && $0 !~ /void CHyprBar::draw\(/ { infn = 0 }
  END { exit found ? 0 : 1 }
' "$ROOT/default/hypr/plugins/hyprbars/barDeco.cpp" \
  || fail "maximize hover dwell fires while the pointer is parked, not only on motion"
if grep -Fq '▦' "$ROOT/default/hypr/desktop-windows.lua"; then
  fail "hyprbars must not keep a dedicated snap caption button"
fi
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
grep -Fq 'youtube' "$ROOT/default/ultimate/csd-clients.json" \
  || fail "YouTube PWAs keep hyprbars:no_bar after dropping the chromium tag"
if grep -Fq 'disable-features=WaylandWindowDecorations' "$ROOT/config/chromium-flags.conf"; then
  fail "Chromium must keep Wayland CSD so hyprbars is not a second title bar"
fi
if grep -Fq 'disable-features=WaylandWindowDecorations' "$ROOT/config/chrome-flags.conf"; then
  fail "Chrome must keep Wayland CSD so hyprbars is not a second title bar"
fi
grep -Fq 'omarchy-shell window close 0x{:x}' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "hyprbars close names the bar's window address"
grep -Fq '^zen$' "$ROOT/default/ultimate/csd-clients.json" \
  || fail "Zen browser no_bar is anchored so zenity keeps hyprbars"
if grep -Fq '|zen|' "$ROOT/default/hypr/desktop-windows.lua"; then
  fail "unanchored zen in desktop-windows would no_bar zenity"
fi
if grep -Fq '|zen|' "$ROOT/default/hypr/apps/browser.lua"; then
  fail "unanchored zen in browser.lua would tag zenity as Firefox"
fi
grep -Fq 'hyprbarsSnapInset' "$ROOT/test/acceptance.d/windows-native-test.sh" \
  || fail "toolkit snap proof uses WindowModel inset, not a hard-coded Chromium +32"
grep -Fq 'm_vDragOrigin' "$ROOT/default/hypr/plugins/hyprbars/barDeco.cpp" \
  || fail "hyprbars must not start a move on sub-threshold motion between title-bar clicks"
grep -Fq 'm_bDraggingThis || inputIsValid()' "$ROOT/default/hypr/plugins/hyprbars/barDeco.cpp" \
  || fail "hyprbars drag end still fires when the pointer is off the title bar"
if grep -Fq 'm_pWindow != window' "$ROOT/default/hypr/plugins/hyprbars/barDeco.cpp"; then
  fail "focused hyprbars must not eat clicks that hit another window"
fi
grep -Fq 'WINDOWATCURSOR != m_pWindow' "$ROOT/default/hypr/plugins/hyprbars/barDeco.cpp" \
  || fail "hyprbars only handles the window under the cursor"
grep -Fq 'm_bDraggingThis || !inputIsValid()' "$ROOT/default/hypr/plugins/hyprbars/barDeco.cpp" \
  || fail "hyprbars maximize hover must not fire for another window's title-bar screen rect"
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
if grep -E '^[^/]*Tokens.surface.glass' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml"; then
  fail "taskbar must not fill with theme glass (Tokyo Night blue)"
fi
if grep -E '^[^/]*Tokens.surface.glass' "$ROOT/shell/plugins/ultimate-start/Start.qml"; then
  fail "Start must not fill with theme glass (Tokyo Night blue)"
fi
if grep -E '^[^/]*Tokens.surface.glass' "$ROOT/shell/plugins/ultimate-taskbar/TaskButton.qml"; then
  fail "taskbar menus must not fill with theme glass (Tokyo Night blue)"
fi
grep -Fq 'Qt.rgba(0.11, 0.11, 0.12, 0.62)' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "Superbar glass is graphite with alpha, not opaque charcoal"
[[ -f $ROOT/default/ultimate/chrome-tokens.json ]] || fail "chrome tokens exist as the Superbar/hyprbars palette"
grep -Fq 'chrome-tokens.json' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "hyprbars caption chrome reads chrome-tokens.json"
grep -Fq 'bar_color = chrome_glass_rgba' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "hyprbars bar_color comes from chrome tokens, not a private rgba"
grep -Fq 'chrome-tokens.json' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "Superbar glass reads chrome-tokens.json"
grep -Fq 'function applyChromeTokens' "$ROOT/shell/plugins/ultimate-taskbar/Taskbar.qml" \
  || fail "Superbar applies chrome tokens after FileView loads"
hlcfg=$(grep -F -c 'hl.config({' "$ROOT/default/hypr/desktop-windows.lua" || true)
(( hlcfg == 1 )) || fail "desktop-windows apply_desktop_look must call hl.config once (parse error otherwise)"
grep -Fq 'bar_blur = true' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "hyprbars title bars use compositor blur"
grep -Fq 'noise = 0' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "Desktop Mode blur must not add film grain"
grep -Fq 'o.window(".*", { opacity = "1 1" })' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "Desktop Mode windows are opaque; 0.985 plus blur is the haze"
grep -Fq 'WaylandWindowDecorations' "$ROOT/config/chrome-flags.conf" \
  || fail "Google Chrome must enable Wayland CSD so min/max/close draw on the tab strip"
grep -Fq 'cm_auto_hdr = 0' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "Desktop Mode must disable cm_auto_hdr so a Samsung HDR EDID cannot haze SDR"
grep -Fq 'namespace = "omarchy-taskbar"' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "Superbar layer is blurred so graphite glass is translucent"
grep -Fq 'namespace = "omarchy-start"' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "Start layer is blurred so the card is translucent"
grep -Fq 'bg_color = "rgb(c8c8c8)"' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "hyprbars min/max must be light rectangles; dark-on-dark looks like only close"
if grep -Fq 'bg_color = "rgb(3d3d3d)"' "$ROOT/default/hypr/desktop-windows.lua"; then
  fail "hyprbars min/max must not be charcoal on a charcoal bar"
fi
grep -Fq '.round = 2' "$ROOT/default/hypr/plugins/hyprbars/barDeco.cpp" \
  || fail "hyprbars caption buttons are rectangles, not traffic-light circles"
if grep -Eq '\.round[[:space:]]*=[[:space:]]*scaledButtonSize' "$ROOT/default/hypr/plugins/hyprbars/barDeco.cpp"; then
  fail "hyprbars must not round caption buttons to circles"
fi
grep -Fq '"id": "google-chrome"' "$ROOT/default/ultimate/taskbar-pins.json" \
  || fail "shipped Chrome pin is Google Chrome so the Superbar gets the real icon"
grep -Fq 'WaylandWindowDecorations' "$ROOT/config/chromium-flags.conf" \
  || fail "Chromium must enable Wayland window decorations (fused tab/caption chrome)"
grep -Fq 'hyprbars:no_bar' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "Desktop Mode hides hyprbars on CSD browsers and Cursor"
grep -Fq '^[Cc]ursor$' "$ROOT/default/ultimate/csd-clients.json" \
  || fail "Desktop Mode hides hyprbars on Cursor CSD"
grep -Fq '[Nn]autilus' "$ROOT/default/ultimate/csd-clients.json" \
  || fail "Files/Nautilus is on the shared CSD list"
grep -Fq 'csd-clients.json' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "desktop windowing loads CSD classes from the shared JSON"
grep -Fq 'csdClassPatterns' "$ROOT/shell/services/WindowModel.js" \
  || fail "WindowModel CSD classes match the shared JSON"
grep -Fq 'omarchy-apply-hyprland-plugins' "$ROOT/bin/omarchy-update" \
  || fail "omarchy-update rebuilds hyprbars and omarchy-minimize after system packages"
awk '
  $0 ~ /omarchy-update-system-pkgs/ { pkgs = 1 }
  pkgs && $0 ~ /omarchy-apply-hyprland-plugins/ { apply = 1 }
  apply && $0 ~ /omarchy-migrate/ { found = 1 }
  END { exit found ? 0 : 1 }
' "$ROOT/bin/omarchy-update" \
  || fail "plugin rebuild is in the update transaction after packages and before migrate"
grep -Fq 'id: "omarchy.agents"' "$ROOT/shell/shell.qml" \
  || fail "Desktop Mode overlay includes omarchy.agents in the Superbar cluster"
grep -Fq 'clusterEntries' "$ROOT/shell/plugins/ultimate-taskbar/TrayCluster.qml" \
  || fail "Superbar notification cluster is driven from bar-widget layout"
if grep -Fq 'persistShellConfig' "$ROOT/shell/shell.qml" && awk '
  $0 ~ /function overlayShellConfig/ { infn = 1 }
  infn && /persistShellConfig/ { found = 1 }
  infn && /^  function / && $0 !~ /function overlayShellConfig/ { infn = 0 }
  END { exit found ? 0 : 1 }
' "$ROOT/shell/shell.qml"; then
  fail "Desktop Mode overlay must not persist shell.json"
fi
grep -Fq '"Close group"' "$ROOT/shell/plugins/ultimate-taskbar/TaskButton.qml" \
  || fail "grouped Superbar close is labeled Close group"
grep -Fq 'function windowIpc' "$ROOT/shell/shell.qml" \
  || fail "window IPC serializes { changed, error }"
grep -Fq 'CapabilityBroker' "$ROOT/shell/shell.qml" \
  || fail "shell wires the capability broker"
[[ -f $ROOT/shell/services/CapabilityBroker.qml ]] || fail "CapabilityBroker.qml exists"
grep -Fq 'capability-ledger.json' "$ROOT/shell/services/CapabilityBroker.qml" \
  || fail "broker records a durable operation ledger"
grep -Fq 'function undoLast' "$ROOT/shell/services/CapabilityBroker.qml" \
  || fail "broker can invert the last window operation"
grep -Fq 'window-placements.json' "$ROOT/shell/services/WindowService.qml" \
  || fail "WindowService remembers per-app reopen placement"
grep -Fq 'function _placeNewClients' "$ROOT/shell/services/WindowService.qml" \
  || fail "reopen memory places mapped clients after compositor rules settle"
grep -Fq 'WindowModel.isLockSurface' "$ROOT/shell/services/WindowService.qml" \
  || fail "reopen memory must not cascade the screensaver into an 880x560 foot"
grep -Fq 'org.omarchy.screensaver' "$ROOT/default/hypr/desktop-windows.lua" \
  || fail "Desktop Mode fullscreen screensaver is excluded from hyprbars"
grep -Fq 'sourceSize.width: 32 * Screen.devicePixelRatio' "$ROOT/shell/plugins/ultimate-taskbar/TaskButton.qml" \
  || fail "Superbar icons request a device-pixel sourceSize so they are not washed out"
grep -Fq 'function _hydrateIfNeeded' "$ROOT/shell/services/WindowService.qml" \
  || fail "reopen memory hydrates existing windows without cascading them"
grep -Fq 'function resizeTo' "$ROOT/shell/shell.qml" \
  || fail "window IPC resizeTo is the same verb as WindowService"
if grep -Fq 'visible: providers.length > 0' "$ROOT/shell/plugins/agents/Panel.qml"; then
  fail "omarchy.agents must stay visible in Desktop Mode even with no usage files"
fi
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
grep -Fq 'start-dismiss-proof.py' "$ROOT/test/acceptance.d/windows-native-test.sh" \
  || fail "windows-native harness runs the Start click-through proof"
[[ -f $ROOT/test/shell.d/start-clickthrough-ipc-test.sh ]] \
  || fail "Start IPC lifecycle test exists for compositor sessions without uinput"
grep -Fq '440x560 omarchy-start card' "$ROOT/test/shell.d/start-clickthrough-ipc-test.sh" \
  || fail "Start IPC test asserts the 440x560 card, not a fullscreen overlay"
grep -Fq 'cycleSnapshot' "$ROOT/test/acceptance.d/hyprbars-pointer-proof.py" \
  || fail "pointer proof aims at the live highlighted Alt+Tab card, not a two-foot layout"
grep -Fq 'unfocused × closed the focused window' "$ROOT/test/acceptance.d/hyprbars-pointer-proof.py" \
  || fail "pointer proof clicks × on an unfocused hyprbars and keeps the focused foot"
grep -Fq 'click on the exposed rear window raises it' "$ROOT/test/acceptance.d/hyprbars-pointer-proof.py" \
  || fail "pointer proof clicks the exposed part of a background window"
grep -Fq 'commitCycle' "$ROOT/test/acceptance.d/windows-native-test.sh" \
  || fail "Alt+Tab harness proves address-change with commitCycle, not only overlay summon"
grep -Fq 'focus_is_not' "$ROOT/test/acceptance.d/windows-native-test.sh" \
  || fail "Alt+Tab harness waits for commitCycle to change focus, not only overlay close"
grep -Fq 'callIfLoaded("omarchy.ultimate-task-switcher", "pick"' "$ROOT/shell/shell.qml" \
  || fail "IPC commitCycle uses switcher pick so overlay unmap cannot restore the previous window"
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

