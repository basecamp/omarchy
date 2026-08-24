#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

script="$ROOT/bin/omarchy-brightness-auto"
unit="$ROOT/default/systemd/user/omarchy-brightness-auto.service"

[[ -x $script ]] || fail "automatic brightness command is installed"
source "$script"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

generic_sensor="$test_tmp/iio/iio:device0"
apple_sensor="$test_tmp/devices/usb/1-1/1-1:1.8/iio:device1"
mkdir -p "$generic_sensor" "$apple_sensor"
printf '50\n' >"$generic_sensor/in_illuminance_input"
printf '05ac\n' >"$test_tmp/devices/usb/1-1/idVendor"
printf '1114\n' >"$test_tmp/devices/usb/1-1/idProduct"
printf '10\n' >"$apple_sensor/in_illuminance_raw"
printf '0.5\n' >"$apple_sensor/in_illuminance_offset"
printf '2\n' >"$apple_sensor/in_illuminance_scale"
ln -s "$apple_sensor" "$test_tmp/iio/iio:device1"

read -r sensor kind < <(find_sensor "$test_tmp/iio")
[[ $sensor == $test_tmp/iio/iio:device1 && $kind == "apple" ]] ||
  fail "Apple ambient sensor is preferred when several sensors exist"
[[ $(read_lux "$sensor") == "21" ]] || fail "raw sensor values use their IIO offset and scale"
[[ $(curve_brightness 200) == "30" ]] || fail "brightness curve keeps its calibrated midpoint"
[[ $(target_with_offset "$(curve_brightness 3276800)" -46) == "89" ]] ||
  fail "a manual baseline does not cap bright-light headroom"
[[ $(smooth_lux 100 200) == "125" ]] || fail "ambient readings are smoothed"
[[ $(step_toward 45 35) == "38" ]] || fail "brightness changes are capped per poll"
pass "automatic brightness sensor and curve behavior"

(
  lux_read_count="$test_tmp/lux-read-count"
  sleep_count="$test_tmp/contention-sleep-count"
  write_count="$test_tmp/contention-write-count"
  contention_writes="$test_tmp/contention-writes"
  printf '0\n' >"$lux_read_count"
  printf '0\n' >"$sleep_count"
  printf '0\n' >"$write_count"
  : >"$contention_writes"
  smoothing_new_weight=1

  read_lux() {
    local count=""
    read -r count <"$lux_read_count"
    printf '%s\n' "$(( count + 1 ))" >"$lux_read_count"
    (( count == 0 )) && printf '200\n' || printf '240\n'
  }
  read_brightness() { printf '30\n'; }
  select_monitor() { printf 'eDP-1\n'; }
  log_state() { :; }
  sleep() {
    local count=""
    read -r count <"$sleep_count"
    (( count < 2 )) || return 1
    printf '%s\n' "$(( count + 1 ))" >"$sleep_count"
  }
  write_brightness() {
    local count=""
    read -r count <"$write_count"
    printf '%s\n' "$2" >>"$contention_writes"
    printf '%s\n' "$(( count + 1 ))" >"$write_count"
    (( count > 0 )) || return 75
  }

  control_session ignored generic eDP-1
  [[ $(cat "$contention_writes") == $'32\n32' ]] ||
    fail "a contended automatic write retries without advancing its brightness state"
)
pass "automatic brightness retries a contended write"

indexed_sensor="$test_tmp/iio-indexed/iio:device0"
mkdir -p "$indexed_sensor"
printf '10\n' >"$indexed_sensor/in_illuminance0_raw"
printf '0.5\n' >"$indexed_sensor/in_illuminance0_offset"
printf '2\n' >"$indexed_sensor/in_illuminance_scale"
if ! read -r sensor kind < <(find_sensor "$test_tmp/iio-indexed"); then
  fail "indexed IIO illuminance channels are discovered"
fi
[[ $sensor == $indexed_sensor && $kind == "generic" ]] ||
  fail "indexed IIO illuminance channels are discovered"
[[ $(read_lux "$sensor") == "21" ]] ||
  fail "indexed IIO channels use channel and shared calibration attributes"
pass "automatic brightness supports indexed IIO illuminance channels"

mock_bin="$test_tmp/bin"
systemctl_state="$test_tmp/systemctl-state"
systemctl_calls="$test_tmp/systemctl-calls"
monitors_file="$test_tmp/monitors.json"
mkdir -p "$mock_bin"
printf 'disabled inactive\n' >"$systemctl_state"
printf '%s\n' '[{"name":"eDP-1","make":"BOE","model":"Panel","disabled":false}]' >"$monitors_file"

cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash
[[ ${1:-} == "monitors" && ${2:-} == "-j" ]] || exit 1
cat "$MONITORS_FILE"
SH

cat >"$mock_bin/omarchy-brightness-display" <<'SH'
#!/bin/bash
[[ ${BRIGHTNESS_AVAILABLE:-1} == "1" ]] || exit 1
if (( $# == 2 )) && [[ $1 == "--monitor" ]]; then
  printf '%s\n' "${BRIGHTNESS_VALUE:-30}"
elif (( $# == 4 )) && [[ $1 == "--no-osd" && $2 == "--monitor" ]]; then
  printf '%s\n' "$4" >>"$BRIGHTNESS_WRITES"
else
  exit 2
fi
SH

cat >"$mock_bin/systemctl" <<'SH'
#!/bin/bash
read -r enabled active <"$SYSTEMCTL_STATE"
case "$*" in
  "--user is-enabled --quiet omarchy-brightness-auto.service") [[ $enabled == "enabled" ]] ;;
  "--user is-active --quiet omarchy-brightness-auto.service") [[ $active == "active" ]] ;;
  "--user enable --now omarchy-brightness-auto.service")
    printf 'enabled active\n' >"$SYSTEMCTL_STATE"
    printf '%s\n' "$*" >>"$SYSTEMCTL_CALLS"
    ;;
  "--user disable --now omarchy-brightness-auto.service")
    printf 'disabled inactive\n' >"$SYSTEMCTL_STATE"
    printf '%s\n' "$*" >>"$SYSTEMCTL_CALLS"
    ;;
  *) exit 2 ;;
esac
SH
chmod +x "$mock_bin"/*

run_auto() {
  OMARCHY_AUTO_BRIGHTNESS_IIO_ROOT="$test_tmp/iio-generic" \
    SYSTEMCTL_STATE="$systemctl_state" SYSTEMCTL_CALLS="$systemctl_calls" \
    MONITORS_FILE="$monitors_file" BRIGHTNESS_WRITES="$test_tmp/brightness-writes" \
    PATH="$mock_bin:$PATH" "$script" "$@"
}

mkdir -p "$test_tmp/iio-generic/iio:device0"
printf '200\n' >"$test_tmp/iio-generic/iio:device0/in_illuminance_input"

status=$(run_auto status)
jq -e '.supported == true and .enabled == false and .active == false' <<<"$status" >/dev/null ||
  fail "automatic brightness reports supported disabled state" "$status"
status=$(BRIGHTNESS_AVAILABLE=0 run_auto status)
jq -e '.supported == false' <<<"$status" >/dev/null ||
  fail "automatic brightness hides when its mapped display is not controllable" "$status"
run_auto on
run_auto toggle
grep -Fx -- '--user enable --now omarchy-brightness-auto.service' "$systemctl_calls" >/dev/null ||
  fail "automatic brightness can be enabled"
grep -Fx -- '--user disable --now omarchy-brightness-auto.service' "$systemctl_calls" >/dev/null ||
  fail "automatic brightness can be disabled"
pass "automatic brightness exposes persistent service controls"

session_sensor="$test_tmp/session-sensor"
sleep_count="$test_tmp/sleep-count"
brightness_writes="$test_tmp/brightness-writes"
mkdir -p "$session_sensor"
printf '200\n' >"$session_sensor/in_illuminance_input"
printf '0\n' >"$sleep_count"
: >"$brightness_writes"
cat >"$mock_bin/sleep" <<'SH'
#!/bin/bash
read -r count <"$SLEEP_COUNT"
if (( count == 0 )); then
  printf '[]\n' >"$MONITORS_FILE"
  printf '1\n' >"$SLEEP_COUNT"
  exit 0
fi
exit 1
SH
chmod +x "$mock_bin/sleep"

if MONITORS_FILE="$monitors_file" SLEEP_COUNT="$sleep_count" BRIGHTNESS_WRITES="$brightness_writes" \
  PATH="$mock_bin:$PATH" control_session "$session_sensor" generic eDP-1 2>/dev/null; then
  fail "automatic brightness detects display loss under steady light"
fi
[[ ! -s $brightness_writes ]] || fail "display loss does not write a stale brightness target"
pass "automatic brightness remaps after display loss under steady light"

grep -Fx 'ExecStart=/usr/bin/omarchy-brightness-auto' "$unit" >/dev/null ||
  fail "automatic brightness unit runs the package command"
grep -Fx 'WantedBy=graphical-session.target' "$unit" >/dev/null ||
  fail "automatic brightness unit follows the graphical session"
grep -F 'omarchy-brightness-auto.service' "$ROOT/install/user/first-run/enable-user-units.sh" >/dev/null &&
  fail "automatic brightness must remain opt-in"
pass "automatic brightness ships disabled by default"
