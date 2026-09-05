#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

viewer="$ROOT/bin/omarchy-lab-viewer"
tmpdir=$(mktemp -d)
export HOME="$tmpdir/home"
export OMARCHY_PATH="$ROOT"
export OMARCHY_LAB_STATE_DIR="$HOME/.config/omarchy/lab-vm"
export OMARCHY_LAB_VIEWER_SETTINGS="$OMARCHY_LAB_STATE_DIR/viewer.json"
export OMARCHY_LAB_VM_BIN="$tmpdir/omarchy-lab-vm"
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$HOME" "$tmpdir/bin"

cat >"$OMARCHY_LAB_VM_BIN" <<'SH'
#!/bin/bash
printf '%s\t%s\n' "${OMARCHY_LAB_VIEWER_ZOOM:-}" "$*" >>"$VIEWER_TEST_CALLS"
if [[ $1 == "screenshot" ]]; then
  printf '%s\n' "virsh chatter" "$VIEWER_TEST_IMAGE"
fi
SH
chmod +x "$OMARCHY_LAB_VM_BIN"
export VIEWER_TEST_CALLS="$tmpdir/lab-vm-calls"
export VIEWER_TEST_IMAGE="$tmpdir/lab.png"

# shellcheck disable=SC1090
source "$viewer"

defaults=$(settings_json)
jq -e '.zoom == 100 and .autoResize == true and .cursor == "auto" and .audio == true and .usbRedirection == true and .keepInBar == false and .aspect == ""' <<<"$defaults" >/dev/null ||
  fail "viewer preferences have safe defaults"
pass "viewer preferences have safe defaults"

(
  source "$viewer"
  enqueue_launch_service() { printf '%s\n' enqueue >>"$tmpdir/launch-calls"; }
  launch_viewer
)
rg -qx 'enqueue' "$tmpdir/launch-calls" || fail "launch immediately enqueues its service"
pass "launcher detaches the graphical console from the app scope"

(
  source "$viewer"
  enqueue_launch_service() { return 1; }
  wake_lab_display() { printf '%s\n' wake >>"$tmpdir/relaunch-calls"; }
  focus_viewer() { printf '%s\n' focus >>"$tmpdir/relaunch-calls"; }
  launch_viewer
)
[[ $(paste -sd ' ' "$tmpdir/relaunch-calls") == 'wake focus' ]] || fail "launch wakes and focuses an already-open Lab viewer"
pass "relaunch wakes and focuses the existing graphical console"

(
  source "$viewer"
  viewer_client() { return 1; }
  domain_state() { printf '%s\n' 'shut off'; }
  run_virsh() { printf 'virsh\t%s\n' "$*" >>"$tmpdir/launch-service-calls"; }
  run_viewer() { printf '%s\n' viewer >>"$tmpdir/launch-service-calls"; }
  launch_viewer_service
)
rg -q $'^virsh\tstart omarchy-lab$' "$tmpdir/launch-service-calls" ||
  fail "the launch service starts a stopped Lab domain"
[[ $(tail -n 2 "$tmpdir/launch-service-calls" | paste -sd ' ' -) == $'virsh\tstart omarchy-lab viewer' ]] ||
  fail "the launch service starts the domain before virt-viewer"
pass "the launch service owns domain startup and the graphical console"

(
  source "$viewer"
  viewer_client() { return 1; }
  domain_state() { printf '%s\n' 'running'; }
  run_virsh() { printf 'virsh\t%s\n' "$*" >>"$tmpdir/wake-service-calls"; }
  run_viewer() { printf '%s\n' viewer >>"$tmpdir/wake-service-calls"; }
  launch_viewer_service
)
rg -q $'^virsh\tsend-key omarchy-lab KEY_LEFTCTRL$' "$tmpdir/wake-service-calls" ||
  fail "the launch service wakes an idle Lab display"
[[ $(tail -n 2 "$tmpdir/wake-service-calls" | paste -sd ' ' -) == $'virsh\tsend-key omarchy-lab KEY_LEFTCTRL viewer' ]] ||
  fail "the launch service wakes the display before virt-viewer"
pass "the launch service wakes an idle Lab display"

mkdir -p "$OMARCHY_LAB_STATE_DIR"
printf '%s\n' '{"zoom":999,"autoResize":"yes","cursor":"remote","audio":4,"usbRedirection":null,"keepInBar":"yes","aspect":"5:4","unknown":"ignored"}' >"$OMARCHY_LAB_VIEWER_SETTINGS"
sanitized=$(settings_json)
jq -e '.zoom == 100 and .autoResize == true and .cursor == "auto" and .audio == true and .usbRedirection == true and .keepInBar == false and .aspect == "" and (has("unknown") | not)' <<<"$sanitized" >/dev/null ||
  fail "viewer preferences reject invalid or unknown values"
pass "viewer preferences reject invalid or unknown values"

update_setting zoom 125
update_setting cursor local
update_setting audio false
update_setting usb-redirection false
update_setting keep-in-bar true
args=$(viewer_args | tr '\0' '\n')
printf '%s\n' "$args" | rg -qx -- '--zoom=125' || fail "saved zoom reaches virt-viewer"
printf '%s\n' "$args" | rg -qx -- '--auto-resize=always' || fail "zoom and automatic guest resizing can be combined"
printf '%s\n' "$args" | rg -qx -- '--cursor=local' || fail "saved cursor mode reaches virt-viewer"
printf '%s\n' "$args" | rg -qx -- '--hotkeys=toggle-fullscreen=shift\+f11,release-cursor=shift\+f12' ||
  fail "viewer keeps valid emergency fullscreen and cursor-release hotkeys"
if printf '%s\n' "$args" | rg -q 'zoom-(in|out|reset)='; then
  fail "viewer does not install hotkeys rejected by virt-viewer"
fi
printf '%s\n' "$args" | rg -qx -- '--spice-disable-audio' || fail "disabled audio reaches virt-viewer"
printf '%s\n' "$args" | rg -qx -- '--spice-disable-usbredir' || fail "disabled USB redirection reaches virt-viewer"
pass "saved preferences produce the virt-viewer command"

rg -q -- '--setenv=OMARCHY_PATH=' "$viewer" || fail "viewer restarts preserve the selected Omarchy tree"
pass "viewer restarts preserve the selected Omarchy tree"

jq -e '.zoom == 125 and .autoResize == true and .keepInBar == true' "$OMARCHY_LAB_VIEWER_SETTINGS" >/dev/null ||
  fail "custom zoom remains compatible with automatic resizing"
pass "zoom and automatic resize remain compatible"

inactive_bar_status=$( (viewer_active() { return 1; }; bar_status_json) )
jq -e '.viewerActive == false and .keepInBar == true' <<<"$inactive_bar_status" >/dev/null ||
  fail "bar status keeps the saved pin visible without a viewer"
active_bar_status=$( (viewer_active() { return 0; }; active_viewer --json) )
jq -e '.viewerActive == true and .keepInBar == true' <<<"$active_bar_status" >/dev/null ||
  fail "bar status distinguishes an open viewer from a saved pin"
pass "bar status is lightweight and machine-readable"

: >"$tmpdir/setting-restarts"
(
  restart_viewer() { printf '%s\n' restart >>"$tmpdir/setting-restarts"; }
  confirmation=$(set_viewer_setting keep-in-bar false)
  [[ $confirmation == "Keep in bar: off" ]] || fail "bar preference prints a concise confirmation"
  [[ ! -s $tmpdir/setting-restarts ]] || fail "bar visibility does not restart virt-viewer"
  set_viewer_setting audio true >/dev/null
  [[ $(wc -l <"$tmpdir/setting-restarts") == 1 ]] || fail "virt-viewer settings still restart an open console"
)
pass "bar visibility changes without disturbing the viewer and confirms concisely"

viewer_service_active() { return 0; }
viewer_client() { printf '%s\n' '{"address":"0xabc","fullscreen":1,"size":[1400,900]}'; }
start_viewer_service() { printf '%s\n' start >>"$tmpdir/restarts"; }
wait_for_viewer() { printf '%s\n' wait >>"$tmpdir/restarts"; }

viewer_service_active() { return 1; }
viewer_active || fail "a directly launched viewer is active without the transient service"
viewer_service_active() { return 0; }
pass "viewer presence does not depend on its launcher"

: >"$VIEWER_TEST_CALLS"
: >"$tmpdir/restarts"
write_settings "$(settings_json | jq -c '.zoom = 125 | .autoResize = true | .aspect = ""')"
set_aspect 16:9 >/dev/null
[[ $(wc -l <"$VIEWER_TEST_CALLS") == 1 ]] || fail "aspect is applied exactly once when auto-resize is already active"
rg -q $'^125\taspect 16:9$' "$VIEWER_TEST_CALLS" || fail "aspect sizing receives the saved viewer zoom"
[[ ! -s $tmpdir/restarts ]] || fail "aspect does not restart an already auto-resizing viewer"

update_setting auto-resize false
: >"$VIEWER_TEST_CALLS"
: >"$tmpdir/restarts"
set_aspect 4:3 >/dev/null
[[ $(wc -l <"$VIEWER_TEST_CALLS") == 1 ]] || fail "aspect is applied exactly once after enabling auto-resize"
[[ $(wc -l <"$tmpdir/restarts") == 2 ]] || fail "aspect restarts a viewer that had auto-resize disabled"
jq -e '.zoom == 125 and .autoResize == true and .aspect == "4:3"' "$OMARCHY_LAB_VIEWER_SETTINGS" >/dev/null ||
  fail "aspect persists and enables automatic guest resizing"
pass "aspect changes persist without duplicate resizing"

hyprctl() {
  printf '%s\n' "$*" >>"$tmpdir/hypr-calls"
  [[ ${2:-} != hl.dsp.window.fullscreen* && ${2:-} != hl.dsp.focus* ]]
}
: >"$tmpdir/hypr-calls"
toggle_fullscreen
rg -Fqx 'dispatch hl.dsp.focus({ window = "address:0xabc" })' "$tmpdir/hypr-calls" ||
  fail "fullscreen fallback first uses the Quattro focus dispatcher"
rg -q '^dispatch focuswindow address:0xabc$' "$tmpdir/hypr-calls" || fail "fullscreen fallback focuses the Lab viewer"
rg -q '^dispatch fullscreen 0$' "$tmpdir/hypr-calls" || fail "fullscreen fallback toggles in either direction"
pass "fullscreen and focus use the Hyprland compatibility fallback"

status_json() {
  printf '%s\n' '{"state":"running","viewerActive":true,"display":"1920x1080","aspect":"16:9","zoom":125,"keepInBar":false}'
}
human_status=$(status_viewer)
printf '%s\n' "$human_status" | rg -qx 'VM: running' || fail "human status includes VM state"
printf '%s\n' "$human_status" | rg -qx 'Display: 1920x1080' || fail "human status includes guest display"
printf '%s\n' "$human_status" | rg -qx 'Zoom: 125%' || fail "human status includes zoom"
printf '%s\n' "$human_status" | rg -qx 'Bar icon: viewer only' || fail "human status includes the bar preference"
[[ $(status_viewer --json) == '{"state":"running","viewerActive":true,"display":"1920x1080","aspect":"16:9","zoom":125,"keepInBar":false}' ]] ||
  fail "JSON status remains machine-readable"
pass "viewer status supports people and the shell plugin"

omarchy-notification-send() { printf '%s\t%s\n' "$1" "$2" >"$tmpdir/notification"; }
touch "$VIEWER_TEST_IMAGE"
[[ $(screenshot_viewer) == "$VIEWER_TEST_IMAGE" ]] || fail "viewer screenshot prints only the saved image path"
rg -q $'^Lab screenshot saved\t'"$VIEWER_TEST_IMAGE"'$' "$tmpdir/notification" ||
  fail "viewer screenshot sends the saved image path in its notification"
pass "viewer screenshot returns and announces one usable path"

domain_running() { return 0; }
: >"$VIEWER_TEST_CALLS"
reboot_lab
rg -q $'^\tssh sudo systemctl reboot --no-wall$' "$VIEWER_TEST_CALLS" ||
  fail "viewer reboot asks the guest OS to reboot cleanly"
if rg -q 'virsh reboot' "$VIEWER_TEST_CALLS"; then
  fail "viewer reboot does not send the guest an ACPI power-button event"
fi
pass "viewer reboot bypasses the guest power menu"

restore_aspect() { printf '%s\n' restored >"$tmpdir/restored-aspect"; }
wait_for_viewer() { return 0; }
write_settings "$(settings_json | jq -c '.autoResize = true | .aspect = "16:10"')"
schedule_restore_aspect
wait "$!"
[[ -f $tmpdir/restored-aspect ]] || fail "opening a viewer restores its saved aspect"
rm -f "$tmpdir/restored-aspect"
OMARCHY_LAB_VIEWER_SKIP_RESTORE=1 schedule_restore_aspect
sleep 0.1
[[ ! -f $tmpdir/restored-aspect ]] || fail "preference restarts do not race a second aspect restore"
pass "viewer launch restores a saved aspect exactly once"

systemctl() { printf 'systemctl\t%s\n' "$*" >>"$tmpdir/viewer-close"; }
viewer_client_pids() { printf '%s\n' 4321 not-a-pid; }
kill() { printf 'kill\t%s\n' "$*" >>"$tmpdir/viewer-close"; }
viewer_checks=0
viewer_client() {
  viewer_checks=$((viewer_checks + 1))
  ((viewer_checks < 2))
}
sleep() { :; }
: >"$tmpdir/viewer-close"
close_viewer_clients
rg -q $'^systemctl\t--user stop app-omarchy-lab-viewer.service$' "$tmpdir/viewer-close" ||
  fail "viewer restart stops its managed service"
rg -q $'^kill\t4321$' "$tmpdir/viewer-close" || fail "viewer restart closes a directly launched console"
if rg -q 'not-a-pid' "$tmpdir/viewer-close"; then
  fail "viewer restart only signals numeric client pids"
fi
pass "viewer restart replaces managed and directly launched consoles"
