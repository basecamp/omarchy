#!/bin/bash

# Executable skeleton for WINDOWS_NATIVE_ACCEPTANCE.md — the forty-task
# Windows-native release gate, run in the disposable-VM acceptance suite.
# Cases land here as vertical slices ship; a case with no implementation yet
# reports "skip" so the manifest stays honest about coverage without failing
# the suite. When a case gains steps, replace its skip line with real checks
# using the base-test.sh helpers (pass/fail/wait_until/layer_present/...).

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

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
    .[] | select(.address == $addr) | select(.workspace.id == $active)
  ' >/dev/null
}

window_is_minimized() {
  local addr="$1"
  hyprctl -j clients | jq -e --arg addr "$addr" '
    .[] | select(.address == $addr)
    | select(.workspace.name == "special:minimized" or .mapped == false or .hidden == true)
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
  close_windows "^foot$"
  for ((i = 0; i < want; i++)); do
    launch_app foot
  done
  wait_until "$want foot windows are open" 30 foot_at_least "$want"
}

restore_native_windows() {
  close_windows "^foot$" >/dev/null 2>&1 || true
  omarchy-shell window commitCycle >/dev/null 2>&1 || true
  omarchy-shell shell hide omarchy.ultimate-task-switcher >/dev/null 2>&1 || true
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
    ;;
  "use Alt+Tab")
    launch_feet 2
    omarchy-shell window cycleNext >/dev/null
    wait_until "task switcher overlay is visible" 10 layer_present "omarchy-task-switcher"
    screenshot "success-alt-tab"
    omarchy-shell window commitCycle >/dev/null
    wait_until "task switcher overlay closes" 10 layer_absent "omarchy-task-switcher"
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

trap - EXIT
restore_native_windows

exit $status
