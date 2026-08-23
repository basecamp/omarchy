#!/bin/bash

# Executable skeleton for WINDOWS_NATIVE_ACCEPTANCE.md — the forty-task
# Windows-native release gate, run in the disposable-VM acceptance suite.
# Cases land here as vertical slices ship; a case with no implementation yet
# reports "skip" so the manifest stays honest about coverage without failing
# the suite. When a case gains steps, replace its skip line with real checks
# using the base-test.sh helpers (pass/fail/wait_until/layer_present/...).

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Do not hyprctl-eval monitor modes here. This Samsung HDMI TV's preferred
# mode is 4K@30 (no-signal). Runtime modesets on the NVIDIA card plus a later
# reload/reboot of stock `preferred` in monitors.lua black the panel. The
# live output is already pinned in ~/.config/hypr/monitors.lua.
PREEXISTING_ADDRS=$(hyprctl -j clients | jq -r '.[].address' | sort)


MANIFEST="$ROOT/WINDOWS_NATIVE_ACCEPTANCE.md"
PINS_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/ultimate/taskbar-pins.json"

tasks=(
  "install the OS"
  "connect Wi-Fi"
  "set display scaling to 125%"
  "change the wallpaper"
  "pair Bluetooth headphones"
  "adjust output volume"
  "install Firefox or Chrome"
  "install Steam"
  "open Downloads"
  "create a folder"
  "rename it"
  "copy files"
  "zip them"
  "connect a USB drive"
  "eject it"
  "connect to an SMB share"
  "open a PDF"
  "edit a text file"
  "change the default browser"
  "pin an app"
  "unpin an app"
  "minimize three windows"
  "restore the one they want"
  "snap two windows"
  "use Alt+Tab"
  "find an application that is consuming CPU"
  "disable a startup application"
  "install system updates"
  "inspect update history"
  "create a restore point"
  "roll back a deliberately broken update"
  "add a printer"
  "change keyboard layout"
  "enable night light"
  "change power mode"
  "install one known-compatible .exe"
  "uninstall it"
  "find system/storage information"
  "troubleshoot intentionally broken audio"
  "shut down"
)

# The manifest document and the harness task list must never drift apart.
manifest_tasks=$(grep -cE '^\| [0-9]+ \|' "$MANIFEST")
if ((manifest_tasks != ${#tasks[@]})); then
  fail "manifest/harness drift" "WINDOWS_NATIVE_ACCEPTANCE.md lists $manifest_tasks tasks; harness enumerates ${#tasks[@]}"
fi
pass "acceptance manifest and harness agree on ${#tasks[@]} tasks"

foot_addresses() {
  hyprctl -j clients | jq -r '.[] | select(.class | test("^foot$")) | .address'
}

foot_count() {
  foot_addresses | grep -c . || true
}

foot_at_least() {
  local n
  n=$(foot_count)
  (( n >= $1 ))
}

window_on_active_workspace() {
  local addr="$1"
  local active
  active=$(hyprctl activeworkspace -j | jq -r .id)
  hyprctl -j clients | jq -e --arg addr "$addr" --argjson active "$active" '
    .[] | select(.address == $addr) | select(.workspace.id == $active and .hidden != true)
  ' >/dev/null
}

window_is_minimized() {
  local addr="$1"
  hyprctl -j clients | jq -e --arg addr "$addr" '
    .[] | select(.address == $addr)
    | select(.hidden == true)
    | select(.workspace.name != "special:minimized")
  ' >/dev/null
}

focused_monitor_json() {
  hyprctl -j monitors | jq -c '.[] | select(.focused == true)'
}

# Hyprland 0.56 reserved is [left, top, right, bottom], not the older wiki TRBL order.
work_area_json() {
  focused_monitor_json | jq -c '{
    x: .reserved[0],
    y: .reserved[1],
    w: (.width - .reserved[0] - .reserved[2]),
    h: (.height - .reserved[1] - .reserved[3]),
    left: .reserved[0],
    top: .reserved[1],
    right: .reserved[2],
    bottom: .reserved[3]
  }'
}

taskbar_reserves_bottom() {
  local area
  area=$(work_area_json)
  # Desktop Mode's only exclusive chrome is the bottom taskbar. A ghost top
  # reserved band (the 173px leak) would make snap follow a false work area.
  jq -e '.bottom >= 32 and .left < 16 and .top < 8 and .right < 8' <<<"$area" >/dev/null
}

window_near_rect() {
  local addr="$1"
  local x="$2"
  local y="$3"
  local w="$4"
  local h="$5"
  hyprctl -j clients | jq -e --arg addr "$addr" --argjson x "$x" --argjson y "$y" --argjson w "$w" --argjson h "$h" '
    .[] | select(.address == $addr)
    | (((.at[0] - $x) | fabs) <= 8)
    and (((.at[1] - $y) | fabs) <= 8)
    and (((.size[0] - $w) | fabs) <= 8)
    and (((.size[1] - $h) | fabs) <= 8)
  ' >/dev/null
}

window_is_maximized() {
  local addr="$1"
  local area
  area=$(work_area_json)
  # hyprctl size is the client box. hyprbars sits in the top of the work area
  # (~32px), so height can be work-area minus the title bar. The occupied
  # span must still meet the work-area edges within 8px.
  hyprctl -j clients | jq -e --arg addr "$addr" --argjson area "$area" '
    .[] | select(.address == $addr)
    | (.fullscreen == 1)
    and ((.at[0] - $area.x) | fabs) <= 8
    and (.at[1] - $area.y) >= -8
    and (.at[1] - $area.y) <= 40
    and (((.at[0] + .size[0]) - ($area.x + $area.w)) | fabs) <= 8
    and (((.at[1] + .size[1]) - ($area.y + $area.h)) | fabs) <= 8
  ' >/dev/null
}

pin_has() {
  local id="$1"
  [[ -f $PINS_FILE ]] && grep -Fq "\"id\": \"$id\"" "$PINS_FILE"
}

pin_missing() {
  ! pin_has "$1"
}

launch_feet() {
  local want="$1"
  local i
  close_windows "^foot$" >/dev/null 2>&1 || true
  wait_until "previous foot windows are gone" 15 window_absent "^foot$"
  for ((i = 0; i < want; i++)); do
    launch_app foot
  done
  wait_until "$want foot windows are open" 30 foot_at_least "$want"
}

restore_native_windows() {
  close_windows "^foot$" >/dev/null 2>&1 || true
  close_windows "Nautilus|org\\.gnome\\.Nautilus" >/dev/null 2>&1 || true
  close_windows "[Xx][Ee]yes" >/dev/null 2>&1 || true
  close_windows "zenity|Zenity" >/dev/null 2>&1 || true
  close_windows "kdialog|KDialog" >/dev/null 2>&1 || true
  close_windows "gtk-parented-dialog" >/dev/null 2>&1 || true
  pkill -f gtk-parented-dialog.py >/dev/null 2>&1 || true
  omarchy-shell window commitCycle >/dev/null 2>&1 || true
  omarchy-shell shell hide omarchy.ultimate-task-switcher >/dev/null 2>&1 || true
  omarchy-shell shell hide omarchy.ultimate-snap-chooser >/dev/null 2>&1 || true
  # Close only clients this harness mapped. Do not kill the user's Cursor or
  # already-open Chromium on the live box.
  while read -r addr class; do
    [[ -n $addr ]] || continue
    if grep -Fxq "$addr" <<<"$PREEXISTING_ADDRS"; then
      continue
    fi
    if [[ $class == [Cc]ursor ]]; then
      continue
    fi
    omarchy-shell window close "$addr" >/dev/null 2>&1 || true
  done < <(hyprctl -j clients | jq -r '.[] | [.address, .class] | @tsv')
}

trap restore_native_windows EXIT

skip_task() {
  printf 'skip - %s (no automated coverage yet)\n' "$1"
  screenshot "pending-$(printf '%s' "$1" | tr -c 'a-z0-9' -)"
}

status=0
for task in "${tasks[@]}"; do
  case "$task" in
  "pin an app")
    omarchy-shell window ping >/dev/null || fail "window IPC responds for pin"
    omarchy-shell window pin foot >/dev/null
    wait_until "foot is pinned to the taskbar" 10 pin_has foot
    screenshot "success-pin-app"
    pass "pin an app"
    ;;
  "unpin an app")
    omarchy-shell window pin foot >/dev/null
    omarchy-shell window unpin foot >/dev/null
    wait_until "foot is unpinned from the taskbar" 10 pin_missing foot
    screenshot "success-unpin-app"
    pass "unpin an app"
    ;;
  "minimize three windows")
    launch_feet 3
    mapfile -t addrs < <(foot_addresses)
    (( ${#addrs[@]} >= 3 )) || fail "minimize three windows" "only ${#addrs[@]} foot windows"
    omarchy-shell window minimize "${addrs[0]}" >/dev/null
    omarchy-shell window minimize "${addrs[1]}" >/dev/null
    omarchy-shell window minimize "${addrs[2]}" >/dev/null
    wait_until "first window is minimized" 10 window_is_minimized "${addrs[0]}"
    wait_until "second window is minimized" 10 window_is_minimized "${addrs[1]}"
    wait_until "third window is minimized" 10 window_is_minimized "${addrs[2]}"
    screenshot "success-minimize-three"
    pass "minimize three windows"
    ;;
  "restore the one they want")
    launch_feet 3
    mapfile -t addrs < <(foot_addresses)
    (( ${#addrs[@]} >= 3 )) || fail "restore the one they want" "only ${#addrs[@]} foot windows"
    omarchy-shell window minimize "${addrs[0]}" >/dev/null
    omarchy-shell window minimize "${addrs[1]}" >/dev/null
    omarchy-shell window minimize "${addrs[2]}" >/dev/null
    wait_until "window parked before restore" 10 window_is_minimized "${addrs[1]}"
    omarchy-shell window restore "${addrs[1]}" >/dev/null
    wait_until "chosen window is restored" 10 window_on_active_workspace "${addrs[1]}"
    screenshot "success-restore-one"
    pass "restore the one they want"
    ;;
  "snap two windows")
    launch_feet 2
    mapfile -t addrs < <(foot_addresses)
    (( ${#addrs[@]} >= 2 )) || fail "snap two windows" "only ${#addrs[@]} foot windows"
    taskbar_reserves_bottom || fail "snap two windows" "taskbar exclusive zone is not the bottom reserved edge: $(work_area_json)"
    omarchy-shell window snapLeft "${addrs[0]}" >/dev/null
    omarchy-shell window snapRight "${addrs[1]}" >/dev/null
    sleep 1
    area=$(work_area_json)
    left_x=$(jq -r .x <<<"$area")
    # hyprctl at/size is the client box. hyprbars (32px) sits above it, so the
    # client is inset from the work-area top so the title bar stays on screen.
    left_y=$(jq -r '.y + 32' <<<"$area")
    left_h=$(jq -r '.h - 32' <<<"$area")
    half=$(jq -r '.w / 2 | floor' <<<"$area")
    right_x=$((left_x + half))
    right_w=$(jq -r .w <<<"$area")
    right_w=$((right_w - half))
    window_near_rect "${addrs[0]}" "$left_x" "$left_y" "$half" "$left_h" \
      || fail "snap two windows" "left geometry was not the work-area left half: $(hyprctl -j clients | jq --arg a "${addrs[0]}" '.[] | select(.address == $a) | {at,size}') work=$(work_area_json)"
    window_near_rect "${addrs[1]}" "$right_x" "$left_y" "$right_w" "$left_h" \
      || fail "snap two windows" "right geometry was not the work-area right half: $(hyprctl -j clients | jq --arg a "${addrs[1]}" '.[] | select(.address == $a) | {at,size}') work=$(work_area_json)"
    screenshot "success-snap-two"
    pass "snap two windows"
    omarchy-shell window snapTo "${addrs[0]}" tl >/dev/null
    sleep 1
    qh=$(jq -r '((.h - 32) / 2) | floor' <<<"$area")
    window_near_rect "${addrs[0]}" "$left_x" "$left_y" "$half" "$qh" \
      || fail "snap two windows" "top-left quarter was wrong: $(hyprctl -j clients | jq --arg a "${addrs[0]}" '.[] | select(.address == $a) | {at,size}')"
    screenshot "success-snap-quarter"
    pass "snap top-left quarter"
    ;;
  "use Alt+Tab")
    launch_feet 2
    mapfile -t addrs < <(foot_addresses)
    (( ${#addrs[@]} >= 2 )) || fail "use Alt+Tab" "only ${#addrs[@]} foot windows"
    last="${addrs[-1]}"
    omarchy-shell window focus "$last" >/dev/null
    before=$(hyprctl -j activewindow | jq -r .address)
    omarchy-shell window cycleNext >/dev/null
    wait_until "task switcher overlay is visible" 10 layer_present "omarchy-task-switcher"
    screenshot "success-alt-tab"
    omarchy-shell window commitCycle >/dev/null
    wait_until "task switcher overlay closes" 10 layer_absent "omarchy-task-switcher"
    after=$(hyprctl -j activewindow | jq -r .address)
    [[ $after != "$before" ]] || fail "use Alt+Tab" "commitCycle kept focus on $before; expected the other foot"
    screenshot "success-alt-tab-commit"
    pass "use Alt+Tab"
    ;;
  *)
    skip_task "$task"
    ;;
  esac
done

# Maximize is not a numbered acceptance row, but the windowing gate requires it.
# These extra proofs fail the file if geometry is wrong; they are not a self-graded go.
launch_feet 1
mapfile -t addrs < <(foot_addresses)
(( ${#addrs[@]} >= 1 )) || fail "maximize fills the work area" "no foot window"
omarchy-shell window maximize "${addrs[0]}" >/dev/null
wait_until "maximized window fills the work area" 10 window_is_maximized "${addrs[0]}"
screenshot "success-maximize"
omarchy-shell window unmaximize "${addrs[0]}" >/dev/null
pass "maximize fills the work area"

hyprctl plugin list 2>/dev/null | grep -qi hyprbars \
  || fail "hyprbars is loaded" "$(hyprctl plugin list 2>/dev/null || true)"
pass "hyprbars is loaded"
hypr_pid=$(pgrep -n Hyprland || true)
[[ -n $hypr_pid ]] || fail "hyprbars is loaded from a tree or /usr/lib plugin" "Hyprland is not running"
if ! grep -E '/usr/lib/hyprland-plugins/hyprbars\.so|/default/hypr/plugins/hyprbars/hyprbars\.so' /proc/$hypr_pid/maps >/dev/null; then
  fail "hyprbars is loaded from a tree or /usr/lib plugin" "$(awk '{print $6}' /proc/$hypr_pid/maps | sort -u | grep hypr || true)"
fi
pass "hyprbars is loaded from a tree or /usr/lib plugin"
if grep -Fq '/var/cache/hyprpm/' /proc/$hypr_pid/maps; then
  fail "hyprbars must not be loaded from the hyprpm cache" "$(awk '{print $6}' /proc/$hypr_pid/maps | sort -u | grep hypr || true)"
fi
hyprctl plugin list 2>/dev/null | grep -qi omarchy-minimize \
  || fail "omarchy-minimize is loaded" "$(hyprctl plugin list 2>/dev/null || true)"
pass "omarchy-minimize is loaded"
layer_absent "omarchy-window-chrome" || fail "overlay captions are gone" "omarchy-window-chrome still mapped"
pass "overlay captions are gone"

launch_feet 1
mapfile -t addrs < <(foot_addresses)
(( ${#addrs[@]} >= 1 )) || fail "restoreNormal unsnaps" "no foot window"
omarchy-shell window snapRight "${addrs[0]}" >/dev/null
sleep 1
omarchy-shell window restoreNormal "${addrs[0]}" >/dev/null
sleep 1
area=$(work_area_json)
half=$(jq -r '.w / 2 | floor' <<<"$area")
hyprctl -j clients | jq -e --arg addr "${addrs[0]}" --argjson half "$half" '
  .[] | select(.address == $addr) | (.size[0] < $half - 8)
' >/dev/null || fail "restoreNormal unsnaps" "window still at snap width: $(hyprctl -j clients | jq --arg a "${addrs[0]}" '.[] | select(.address == $a) | {at,size}')"
pass "restoreNormal unsnaps to an overlapping float"

launch_feet 2
mapfile -t addrs < <(foot_addresses)
(( ${#addrs[@]} >= 2 )) || fail "Win+Arrow quarters" "need two feet"
omarchy-shell window snapTo "${addrs[0]}" l >/dev/null
sleep 1
omarchy-shell window snapArrow "${addrs[0]}" u >/dev/null
sleep 1
area=$(work_area_json)
left_x=$(jq -r .x <<<"$area")
left_y=$(jq -r '.y + 32' <<<"$area")
half=$(jq -r '.w / 2 | floor' <<<"$area")
qh=$(jq -r '((.h - 32) / 2) | floor' <<<"$area")
window_near_rect "${addrs[0]}" "$left_x" "$left_y" "$half" "$qh" \
  || fail "Win+Arrow quarters" "left then up was not top-left: $(hyprctl -j clients | jq --arg a "${addrs[0]}" '.[] | select(.address == $a) | {at,size}')"
pass "Win+Arrow left then up is the top-left quarter"

omarchy-shell window snapTo "${addrs[0]}" l >/dev/null
omarchy-shell window snapTo "${addrs[1]}" r >/dev/null
sleep 1
omarchy-shell window saveLayout >/dev/null
omarchy-shell window restoreNormal "${addrs[0]}" >/dev/null
omarchy-shell window restoreNormal "${addrs[1]}" >/dev/null
sleep 1
omarchy-shell window restoreLayout >/dev/null
sleep 1
left_h=$(jq -r '.h - 32' <<<"$area")
right_x=$((left_x + half))
right_w=$(jq -r .w <<<"$area")
right_w=$((right_w - half))
window_near_rect "${addrs[0]}" "$left_x" "$left_y" "$half" "$left_h" \
  || fail "restoreLayout" "first foot did not return to the left half: $(hyprctl -j clients | jq --arg a "${addrs[0]}" '.[] | select(.address == $a) | {at,size}')"
window_near_rect "${addrs[1]}" "$right_x" "$left_y" "$right_w" "$left_h" \
  || fail "restoreLayout" "second foot did not return to the right half: $(hyprctl -j clients | jq --arg a "${addrs[1]}" '.[] | select(.address == $a) | {at,size}')"
pass "saveLayout then restoreLayout returns the snapped pair"

omarchy-shell window snapChooser "${addrs[0]}" >/dev/null
wait_until "snap layout chooser is visible" 10 layer_present "omarchy-snap-chooser"
screenshot "success-snap-chooser"
omarchy-shell shell hide omarchy.ultimate-snap-chooser >/dev/null || true
wait_until "snap layout chooser closes" 10 layer_absent "omarchy-snap-chooser"
pass "snap layout chooser summons omarchy-snap-chooser"

omarchy-shell window restoreNormal "${addrs[0]}" >/dev/null
sleep 1
omarchy-shell window aeroDragEnd "${addrs[0]}" 960 0 >/dev/null
wait_until "aero drag to top maximizes" 10 window_is_maximized "${addrs[0]}"
pass "aeroDragEnd at the top edge maximizes"
omarchy-shell window aeroDragEnd "${addrs[0]}" 960 400 >/dev/null
sleep 1
hyprctl -j clients | jq -e --arg a "${addrs[0]}" '.[] | select(.address == $a) | .fullscreen == 0' >/dev/null \
  || fail "drag-away restore" "interior aeroDragEnd left the window maximized: $(hyprctl -j clients | jq --arg a "${addrs[0]}" '.[] | select(.address == $a) | {at,size,fullscreen}')"
pass "aeroDragEnd away from an edge restores"

omarchy-shell window toggleShowDesktop >/dev/null
sleep 1
hidden=$(hyprctl -j clients | jq '[.[] | select(.class == "foot" and .hidden == true)] | length')
(( hidden >= 1 )) || fail "Show Desktop" "no foot is hidden after Win+D: $(hyprctl -j clients | jq '[.[] | select(.class == "foot") | {address,hidden}]')"
omarchy-shell window toggleShowDesktop >/dev/null
sleep 1
pass "Show Desktop hides and restores"

home_ws=$(hyprctl -j activeworkspace | jq -r .id)
omarchy-shell window createDesktop >/dev/null
sleep 1
created_ws=$(hyprctl -j activeworkspace | jq -r .id)
(( created_ws != home_ws )) || fail "new desktop" "active workspace stayed $home_ws"
omarchy-shell window switchToDesktop "$home_ws" >/dev/null
sleep 1
now_ws=$(hyprctl -j activeworkspace | jq -r .id)
(( now_ws == home_ws )) || fail "switch desktop" "did not return to desktop $home_ws: $now_ws"
omarchy-shell window moveToDesktop "${addrs[0]}" "$created_ws" >/dev/null
sleep 1
stay_ws=$(hyprctl -j activeworkspace | jq -r .id)
(( stay_ws == home_ws )) || fail "move to desktop" "follow stole the current desktop: $stay_ws"
foot_on_created=$(hyprctl -j clients | jq --arg a "${addrs[0]}" '.[] | select(.address == $a) | .workspace.id')
(( foot_on_created == created_ws )) || fail "move to desktop" "window stayed on $foot_on_created not $created_ws"
omarchy-shell window switchToDesktop "$created_ws" >/dev/null
sleep 0.5
omarchy-shell window closeDesktop >/dev/null
sleep 1
ws_after=$(hyprctl -j activeworkspace | jq -r .id)
(( ws_after != created_ws )) || fail "close desktop" "active workspace stayed $created_ws"
still=$(hyprctl -j workspaces | jq --argjson id "$created_ws" '[.[] | select(.id == $id)] | length')
(( still == 0 )) || fail "close desktop" "desktop $created_ws is still listed: $(hyprctl -j workspaces | jq -c '[.[] | {id,windows}]')"
foot_home=$(hyprctl -j clients | jq --arg a "${addrs[0]}" '.[] | select(.address == $a) | .workspace.id')
(( foot_home == ws_after )) || fail "close desktop" "window is on $foot_home not $ws_after"
pass "virtual desktops create, move, switch, and close"

omarchy-shell window taskView >/dev/null
wait_until "Task View is visible" 10 layer_present "omarchy-task-switcher"
screenshot "success-task-view"
omarchy-shell shell hide omarchy.ultimate-task-switcher >/dev/null || true
wait_until "Task View closes" 10 layer_absent "omarchy-task-switcher"
pass "Task View summons omarchy-task-switcher"

omarchy-shell window restoreNormal "${addrs[0]}" >/dev/null
sleep 1
omarchy-shell window toggleFullscreen "${addrs[0]}" >/dev/null
sleep 1
fs=$(hyprctl -j clients | jq --arg a "${addrs[0]}" '.[] | select(.address == $a) | .fullscreen')
(( fs == 2 )) || fail "fullscreen" "fullscreen is $fs not 2"
omarchy-shell window toggleFullscreen "${addrs[0]}" >/dev/null
sleep 1
pass "F11-class fullscreen toggles"

primary_name=$(hyprctl -j monitors | jq -r '.[] | select(.focused == true) | .name' | head -1)
if [[ -z $primary_name ]]; then
  primary_name=$(hyprctl -j monitors | jq -r '.[0].name')
fi
created_headless=""
second_name=$(hyprctl -j monitors | jq -r --arg p "$primary_name" '[.[] | select(.name != $p and ((.disabled // false) | not))] | .[0].name // empty')
if [[ -n $second_name ]]; then
  second_w=$(hyprctl -j monitors | jq -r --arg n "$second_name" '.[] | select(.name == $n) | .width')
  if (( second_w <= 1024 )); then
    second_name=""
  fi
fi
if [[ -z $second_name ]]; then
  hyprctl output create headless HEADLESS-2 >/dev/null 2>&1 || hyprctl output create headless >/dev/null 2>&1 || true
  sleep 0.5
  # Prefer the new headless output. Do not pick a disabled phantom DP or the
  # live HDMI TV — eval'ing those re-modesets the NVIDIA card.
  second_name=$(hyprctl -j monitors | jq -r --arg p "$primary_name" '[.[] | select(.name != $p and (.name | startswith("HEADLESS")))] | .[0].name // empty')
  created_headless=$second_name
fi
if [[ $second_name == HDMI-A-1 || $second_name == HDMI-* ]]; then
  second_name=""
fi
if [[ -n $second_name ]]; then
  if [[ $second_name == HEADLESS* ]]; then
    hyprctl eval "hl.monitor({ output = \"$second_name\", mode = \"1920x1080@60\", position = \"1920x0\", scale = 1 })" >/dev/null 2>&1 || true
  fi
  sleep 0.4
  omarchy-shell window restoreNormal "${addrs[0]}" >/dev/null
  sleep 0.5
  omarchy-shell window moveToMonitor "${addrs[0]}" r >/dev/null
  sleep 1
  mon_name=$(hyprctl -j clients | jq -r --arg a "${addrs[0]}" --argjson mons "$(hyprctl -j monitors)" '
    .[] | select(.address == $a) | .monitor as $id | ($mons[] | select(.id == $id) | .name)
  ')
  [[ $mon_name == "$second_name" ]] || fail "move to monitor" "window is on ${mon_name:-none}, expected $second_name"
  omarchy-shell window snapTo "${addrs[0]}" l >/dev/null
  sleep 1
  dest_x=$(hyprctl -j monitors | jq -r --arg n "$second_name" '.[] | select(.name == $n) | .x')
  atx=$(hyprctl -j clients | jq --arg a "${addrs[0]}" '.[] | select(.address == $a) | .at[0]')
  (( atx >= dest_x - 8 && atx <= dest_x + 16 )) || fail "snap on second monitor" "left snap x is $atx, expected near $dest_x"
  pass "window moves to a second monitor and snaps there"
  omarchy-shell window moveToMonitor "${addrs[0]}" l >/dev/null
  sleep 0.5
  hyprctl eval "hl.dsp.focus({ monitor = \"$primary_name\" })" >/dev/null 2>&1 || true
  if [[ -n $created_headless ]]; then
    hyprctl output remove "$created_headless" >/dev/null 2>&1 || true
  fi
else
  fail "multi-monitor" "could not add a second monitor next to $primary_name: $(hyprctl -j monitors)"
fi

prove_toolkit() {
  local name="$1"
  local launch="$2"
  local class_re="$3"
  local bin=${launch%% *}
  command -v "$bin" >/dev/null || fail "$name windowing" "$bin is not on this guest"
  local before addr
  before=$(hyprctl -j clients | jq -r --arg re "$class_re" '.[] | select(.class | test($re)) | .address')
  launch_app "$launch"
  wait_until "$name window is mapped" 40 toolkit_has_new "$class_re" "$before"
  addr=$(toolkit_new_addr "$class_re" "$before")
  [[ -n $addr ]] || fail "$name windowing" "no new client matched $class_re"
  local area half left_x right_x right_w left_y left_h cls inset tries
  cls=$(hyprctl -j clients | jq -r --arg a "$addr" '.[] | select(.address == $a) | .class // empty')
  inset=$(CLASS=$cls node -e 'const m=require(process.argv[1]); process.stdout.write(String(m.hyprbarsSnapInset({class: process.env.CLASS || ""})))' "$ROOT/shell/services/WindowModel.js")
  area=$(work_area_json)
  half=$(jq -r '.w / 2 | floor' <<<"$area")
  left_x=$(jq -r .x <<<"$area")
  right_x=$((left_x + half))
  right_w=$(( $(jq -r .w <<<"$area") - half ))
  left_y=$(jq -r --argjson i "$inset" '.y + $i' <<<"$area")
  left_h=$(jq -r --argjson i "$inset" '.h - $i' <<<"$area")
  tries=0
  while ((tries < 4)); do
    omarchy-shell window snapTo "$addr" r >/dev/null
    sleep 0.6
    window_near_rect "$addr" "$right_x" "$left_y" "$right_w" "$left_h" && break
    tries=$((tries + 1))
  done
  window_near_rect "$addr" "$right_x" "$left_y" "$right_w" "$left_h" \
    || fail "$name snap" "$name did not take the right half (inset $inset): $(hyprctl -j clients | jq --arg a "$addr" '.[] | select(.address == $a) | {class,at,size,xwayland,fullscreen}') work=$(work_area_json)"
  screenshot "success-$name"
  omarchy-shell window close "$addr" >/dev/null 2>&1 || true
  wait_until "$name window closed" 15 window_absent_addr "$addr"
  pass "$name snaps to the right work-area half"
}

window_absent_addr() {
  local addr="$1"
  hyprctl -j clients | jq -e --arg addr "$addr" 'all(.address != $addr)' >/dev/null
}

toolkit_new_addr() {
  hyprctl -j clients | jq -r --arg re "$1" --arg before "$2" '
    .[] | select(.class | test($re)) | .address
    | select(. as $a | ($before == "" or (($before | split("\n") | index($a)) == null)))
  ' | sed -n '1p'
}

toolkit_has_new() {
  [[ -n $(toolkit_new_addr "$1" "$2") ]]
}

prove_toolkit "GTK Nautilus" "nautilus --new-window" "Nautilus|org\\.gnome\\.Nautilus"
prove_toolkit "Chromium" "chromium --user-data-dir=/tmp/omarchy-w0-chromium --no-first-run about:blank" "^[Cc]hromium"

if ! command -v xeyes >/dev/null; then
  fail "XWayland" "xeyes is not installed; this guest cannot probe XWayland windowing"
fi
close_windows "xeyes|^XEyes$|[Xx][Ee]yes" >/dev/null 2>&1 || true
launch_app xeyes
wait_until "XWayland xeyes is mapped" 20 window_present "[Xx][Ee]yes"
xeyes_addr=$(hyprctl -j clients | jq -r '.[] | select(.class | test("[Xx][Ee]yes")) | .address' | head -1)
hyprctl -j clients | jq -e --arg a "$xeyes_addr" '.[] | select(.address == $a) | .xwayland == true' >/dev/null \
  || fail "XWayland" "xeyes is not an XWayland client: $(hyprctl -j clients | jq --arg a "$xeyes_addr" '.[] | select(.address == $a)')"
omarchy-shell window minimize "$xeyes_addr" >/dev/null
sleep 1
window_is_minimized "$xeyes_addr" || fail "XWayland minimize" "xeyes did not hide in place"
omarchy-shell window restore "$xeyes_addr" >/dev/null
sleep 1
close_windows "[Xx][Ee]yes" >/dev/null 2>&1 || true
pass "XWayland client maps, minimizes, and restores"

qt_qml="$ROOT/test/acceptance.d/qt-w0-window.qml"
if command -v qml6 >/dev/null && [[ -f $qt_qml ]]; then
  prove_toolkit "Qt qml6" "qml6 --quiet $qt_qml" "org\\.qt-project\\.qml|qml6|omarchy-w0-qt|QtQmlViewer"
else
  qt_bin=""
  for cand in qt6ct designer assistant; do
    if command -v "$cand" >/dev/null; then
      qt_bin=$cand
      break
    fi
  done
  if [[ -n $qt_bin ]]; then
    prove_toolkit "Qt $qt_bin" "$qt_bin" "$qt_bin"
  else
    fail "Qt windowing" "no resizable Qt window client (qml6/qt6ct) on this disk; a size-locked KDE message box is not the probe"
  fi
fi

electron_bin=""
cursor_mapped=$(hyprctl -j clients | jq -e '.[] | select(.class | test("^[Cc]ursor$"))' >/dev/null && echo yes || echo no)
if [[ $cursor_mapped == yes ]]; then
  cursor_json=$(hyprctl -j clients | jq -c '.[] | select(.class | test("^[Cc]ursor$"))' | sed -n '1p')
  cursor_float=$(jq -r '.floating' <<<"$cursor_json")
  [[ $cursor_float == true ]] || fail "Electron Cursor" "live Cursor is not a Desktop Mode float: $cursor_json"
  pass "Electron Cursor is a mapped Desktop Mode float ($(jq -r '.at, .size' <<<"$cursor_json"))"
else
  for cand in code code-oss obsidian discord slack spotify 1password electron; do
    if command -v "$cand" >/dev/null; then
      electron_bin=$cand
      break
    fi
  done
  if [[ -n $electron_bin ]]; then
    prove_toolkit "Electron $electron_bin" "$electron_bin" "$electron_bin"
  else
    printf 'skip - Electron app is not on this guest disk\n'
  fi
fi

if command -v steam >/dev/null; then
  prove_toolkit "Steam" "steam" "steam|Steam"
else
  printf 'skip - Steam is not on this disk; XWayland is the windowing path\n'
fi
if command -v wine >/dev/null || command -v wine64 >/dev/null; then
  wine_bin=$(command -v wine64 || command -v wine)
  prove_toolkit "Wine" "$wine_bin winecfg" "winecfg|Wine"
else
  printf 'skip - Wine is not on this disk; XWayland is the windowing path\n'
fi

if ! command -v zenity >/dev/null; then
  fail "parented dialog" "zenity is not available to probe an xdg modal"
fi
close_windows "zenity|Zenity" >/dev/null 2>&1 || true
launch_app "zenity --question --text=W0 --ok-label=OK --cancel-label=Cancel"
wait_until "modal zenity is mapped" 20 window_present "zenity|Zenity"
zen_json=$(hyprctl -j clients | jq -c '.[] | select(.class | test("zenity|Zenity"))')
zen_w=$(jq -r '.size[0]' <<<"$zen_json")
zen_modal=$(jq -r '.modal // false' <<<"$zen_json")
(( zen_w < 880 )) || fail "parented dialog" "zenity was forced to the 880px app size: $zen_json"
screenshot "success-modal-dialog"
close_windows "zenity|Zenity" >/dev/null 2>&1 || true
pass "modal dialog keeps its own size (modal=$zen_modal width=$zen_w)"

gtk_py="$ROOT/test/acceptance.d/gtk-parented-dialog.py"
[[ -f $gtk_py ]] || fail "parented dialog" "missing $gtk_py"
pkill -f gtk-parented-dialog.py >/dev/null 2>&1 || true
launch_app "python3 $gtk_py"
wait_until "GTK parented dialog is mapped" 20 window_present "gtk-parented-dialog"
sleep 0.8
gtk_parent=$(hyprctl -j clients | jq -c '.[] | select(.title == "W0-Parent")')
gtk_dialog=$(hyprctl -j clients | jq -c '.[] | select(.title == "W0-Dialog")')
[[ -n $gtk_parent && $gtk_parent != null ]] || fail "parented dialog" "GTK parent missing"
[[ -n $gtk_dialog && $gtk_dialog != null ]] || fail "parented dialog" "GTK dialog missing"
gtk_dw=$(jq -r '.size[0]' <<<"$gtk_dialog")
gtk_dh=$(jq -r '.size[1]' <<<"$gtk_dialog")
gtk_px=$(jq -r '.at[0]' <<<"$gtk_parent")
gtk_py=$(jq -r '.at[1]' <<<"$gtk_parent")
gtk_pw=$(jq -r '.size[0]' <<<"$gtk_parent")
gtk_ph=$(jq -r '.size[1]' <<<"$gtk_parent")
gtk_dx=$(jq -r '.at[0]' <<<"$gtk_dialog")
gtk_dy=$(jq -r '.at[1]' <<<"$gtk_dialog")
(( gtk_dw < 880 && gtk_dh < 560 )) || fail "parented dialog" "GTK dialog was forced to the app size: $gtk_dialog"
(( gtk_dx >= gtk_px - 16 && gtk_dx + gtk_dw <= gtk_px + gtk_pw + 16 )) || fail "parented dialog" "dialog not on parent x: parent=$gtk_parent dialog=$gtk_dialog"
(( gtk_dy >= gtk_py - 16 && gtk_dy + gtk_dh <= gtk_py + gtk_ph + 16 )) || fail "parented dialog" "dialog not on parent y: parent=$gtk_parent dialog=$gtk_dialog"
screenshot "success-gtk-parented-dialog"
pkill -f gtk-parented-dialog.py >/dev/null 2>&1 || true
wait_until "GTK parented dialog closed" 10 window_absent "gtk-parented-dialog"
pass "GTK parented dialog stays small on its parent (${gtk_dw}x${gtk_dh} at ${gtk_dx},${gtk_dy})"

layer_present "omarchy-taskbar" || fail "tray chrome" "taskbar layer is missing"
pass "taskbar tray cluster is mapped"

# Mouse proof: one absolute pointer (USB-tablet class), not relative ydotool.
# Missing /dev/uinput is a failure, not a skip.
run_hyprbars_pointer_proof() {
  local script="$ROOT/test/acceptance.d/hyprbars-pointer-proof.py"
  [[ -f $script ]] || fail "hyprbars pointer proof" "missing $script"
  if [[ ! -e /dev/uinput ]]; then
    fail "hyprbars pointer proof" "/dev/uinput is missing; relative ydotool is not this gate"
  fi
  if [[ -w /dev/uinput ]]; then
    python3 "$script" || fail "hyprbars pointer proof" "absolute pointer did not close, drag, maximize, minimize, and pick an Alt+Tab card"
    return
  fi
  if sudo -n true >/dev/null 2>&1; then
    sudo -n python3 "$script" || fail "hyprbars pointer proof" "absolute pointer did not close, drag, maximize, minimize, and pick an Alt+Tab card"
    return
  fi
  fail "hyprbars pointer proof" "cannot write /dev/uinput and sudo -n is unavailable; relative ydotool is not this gate"
}

run_csd_caption_pointer_proof() {
  local script="$ROOT/test/acceptance.d/csd-caption-pointer-proof.py"
  [[ -f $script ]] || fail "CSD caption pointer proof" "missing $script"
  if [[ ! -e /dev/uinput ]]; then
    fail "CSD caption pointer proof" "/dev/uinput is missing; relative ydotool is not this gate"
  fi
  if [[ -w /dev/uinput ]]; then
    python3 "$script" || fail "CSD caption pointer proof" "Chromium CSD min/max/close click failed"
    return
  fi
  if sudo -n true >/dev/null 2>&1; then
    sudo -n python3 "$script" || fail "CSD caption pointer proof" "Chromium CSD min/max/close click failed"
    return
  fi
  fail "CSD caption pointer proof" "cannot write /dev/uinput and sudo -n is unavailable; relative ydotool is not this gate"
}

run_start_dismiss_proof() {
  local script="$ROOT/test/acceptance.d/start-dismiss-proof.py"
  [[ -f $script ]] || fail "Start dismiss proof" "missing $script"
  if [[ ! -e /dev/uinput ]]; then
    fail "Start dismiss proof" "/dev/uinput is missing; relative ydotool is not this gate"
  fi
  if [[ -w /dev/uinput ]]; then
    python3 "$script" || fail "Start dismiss proof" "outside click, orb, card, or click-through failed"
    return
  fi
  if sudo -n true >/dev/null 2>&1; then
    sudo -n python3 "$script" || fail "Start dismiss proof" "outside click, orb, card, or click-through failed"
    return
  fi
  fail "Start dismiss proof" "cannot write /dev/uinput and sudo -n is unavailable; relative ydotool is not this gate"
}

run_hyprbars_pointer_proof
pass "hyprbars close, title-bar drag, maximize click, minimize click, and Alt+Tab card click via an absolute pointer"
run_csd_caption_pointer_proof
pass "Chromium CSD min/max/close via an absolute pointer (never Cursor)"
run_start_dismiss_proof
pass "Start outside click, orb, card, and click-through via an absolute pointer"

trap - EXIT
restore_native_windows

exit $status
