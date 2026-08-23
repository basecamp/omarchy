#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
mkdir -p "$tmp_dir/power/BAT0"
printf '900000\n' >"$tmp_dir/power/BAT0/current_now"
printf '12000000\n' >"$tmp_dir/power/BAT0/voltage_now"
cat >"$tmp_dir/bin/upower" <<'STUB'
#!/bin/bash

if [[ $1 == "-e" ]]; then
  echo "/org/freedesktop/UPower/devices/battery_BAT0"
  exit 0
fi

if [[ $1 == "-i" ]]; then
  cat <<'INFO'
  native-path:          BAT0
  state:                discharging
  energy:               28.3 Wh
  energy-full:          56.7 Wh
  energy-rate:          7.3 W
  time to empty:        2.5 hours
  percentage:           51%
INFO
  exit 0
fi

exit 1
STUB
chmod +x "$tmp_dir/bin/upower"

shell_output=$(OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power" PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'percentage\t51%' <<<"$shell_output" >/dev/null || fail "battery status reports percentage"
grep -Fx $'state\tdischarging' <<<"$shell_output" >/dev/null || fail "battery status reports state"
grep -Fx $'rate\t10.8W' <<<"$shell_output" >/dev/null || fail "battery status reports live sysfs power rate"
grep -Fx $'size\t56Wh' <<<"$shell_output" >/dev/null || fail "battery status reports full capacity"
grep -Fx $'time\t2h 30m' <<<"$shell_output" >/dev/null || fail "battery status reports remaining time"

if matches=$(rg -n 'omarchy-battery-(capacity|remaining|remaining-time)' "$ROOT/bin" "$ROOT/test" "$ROOT/shell" "$ROOT/docs"); then
  fail "battery status owns capacity and remaining calculations" "$matches"
fi

pass "battery status owns capacity and remaining calculations"

# "pending-charge" only means AC is present and the EC is not charging, so a
# charge-limit hold has to be told apart from a pack the EC refuses for any
# other reason. Build a machine per case rather than mutating one in place.
battery_machine() {
  local state="$1" percentage="$2" start="$3" end="$4"
  local case_dir
  case_dir=$(mktemp -d "$tmp_dir/case.XXXXXX")

  mkdir -p "$case_dir/bin" "$case_dir/power/BAT0" "$case_dir/power/AC"
  printf 'Mains\n' >"$case_dir/power/AC/type"
  printf '1\n' >"$case_dir/power/AC/online"
  printf 'Battery\n' >"$case_dir/power/BAT0/type"
  printf '0\n' >"$case_dir/power/BAT0/power_now"
  printf '%s\n' "$start" >"$case_dir/power/BAT0/charge_control_start_threshold"
  printf '%s\n' "$end" >"$case_dir/power/BAT0/charge_control_end_threshold"

  {
    printf '#!/bin/bash\n'
    printf 'if [[ $1 == "-e" ]]; then echo /org/freedesktop/UPower/devices/battery_BAT0; exit 0; fi\n'
    printf 'if [[ $1 == "-i" ]]; then\n'
    printf '  echo "  native-path:          BAT0"\n'
    printf '  echo "  state:                %s"\n' "$state"
    printf '  echo "  energy-full:          58.0 Wh"\n'
    printf '  echo "  energy-rate:          0 W"\n'
    printf '  echo "  percentage:           %s%%"\n' "$percentage"
    printf '  exit 0\n'
    printf 'fi\n'
    printf 'exit 1\n'
  } >"$case_dir/bin/upower"
  chmod +x "$case_dir/bin/upower"

  printf '%s' "$case_dir"
}

battery_status_for() {
  local case_dir
  case_dir=$(battery_machine "$@")

  OMARCHY_POWER_SUPPLY_PATH="$case_dir/power" PATH="$case_dir/bin:$PATH" \
    "$ROOT/bin/omarchy-battery-status" --shell
}

battery_line_for() {
  local case_dir
  case_dir=$(battery_machine "$@")

  OMARCHY_POWER_SUPPLY_PATH="$case_dir/power" PATH="$case_dir/bin:$PATH" \
    "$ROOT/bin/omarchy-battery-status"
}

assert_battery_state() {
  local description="$1" expected="$2"
  shift 2
  local output
  output=$(battery_status_for "$@")

  grep -Fx "state	$expected" <<<"$output" >/dev/null ||
    fail "$description" "$output"
  pass "$description"
}

# A dead pack the EC refuses to charge, on a machine with no limit configured.
assert_battery_state "battery status does not call an unheld stall a charge limit" \
  "pending-charge" "pending-charge" 0 0 100

# UPower's hwdb default supplies a 75-80 threshold this machine never set, so
# the level is the only thing that separates a hold from a refusal.
assert_battery_state "battery status does not claim a hold below the threshold band" \
  "pending-charge" "pending-charge" 0 75 80

# A real hold: the pack sat up to the end threshold and the EC stopped.
assert_battery_state "battery status reports a hold inside the threshold band" \
  "holding" "pending-charge" 80 75 80

# A start of 0 is sysfs saying there is no start threshold, not that the limit
# holds from empty.
assert_battery_state "battery status does not read a zero start threshold as holding from empty" \
  "pending-charge" "pending-charge" 40 0 80
assert_battery_state "battery status reports a hold at a lone end threshold" \
  "holding" "pending-charge" 80 0 80

# The notification line has no time estimate to print for a stall, so it has to
# name the state rather than fall through to an empty "left".
line=$(battery_line_for "pending-charge" 0 0 100)
[[ $line == *"Not charging"* && $line != *"left"* ]] ||
  fail "battery status names an unheld stall in the notification line" "$line"
pass "battery status names an unheld stall in the notification line"

line=$(battery_line_for "pending-charge" 80 75 80)
[[ $line == *"Holding at 75-80%"* ]] ||
  fail "battery status still names a real hold in the notification line" "$line"
pass "battery status still names a real hold in the notification line"
