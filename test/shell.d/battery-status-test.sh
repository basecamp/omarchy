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
grep -Fx $'pack.0.path\tBAT0' <<<"$shell_output" >/dev/null || fail "battery status reports the single pack path"
grep -Fx $'pack.0.percentage\t51%' <<<"$shell_output" >/dev/null || fail "battery status reports the single pack percentage"

pass "battery status owns capacity and remaining calculations"

dual_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir" "$dual_dir"' EXIT

mkdir -p "$dual_dir/bin" "$dual_dir/power/BAT0" "$dual_dir/power/BAT1" "$dual_dir/power/AC"
printf 'Mains\n' >"$dual_dir/power/AC/type"
printf '1\n' >"$dual_dir/power/AC/online"
printf '0\n' >"$dual_dir/power/BAT0/power_now"
printf '7\n' >"$dual_dir/power/BAT0/cycle_count"
printf '3611000\n' >"$dual_dir/power/BAT1/power_now"
printf '2\n' >"$dual_dir/power/BAT1/cycle_count"
cat >"$dual_dir/bin/upower" <<'STUB'
#!/bin/bash

if [[ $1 == "-e" ]]; then
  echo "/org/freedesktop/UPower/devices/battery_BAT0"
  echo "/org/freedesktop/UPower/devices/battery_BAT1"
  exit 0
fi

if [[ $1 == "-i" && $2 == *BAT1 ]]; then
  cat <<'INFO'
  native-path:          BAT1
  state:                charging
  energy:               0.09 Wh
  energy-full:          71.04 Wh
  energy-rate:          3.611 W
  time to full:         19.6 hours
  percentage:           0%
  charge-start-threshold:        75%
  charge-end-threshold:          80%
INFO
  exit 0
fi

if [[ $1 == "-i" ]]; then
  cat <<'INFO'
  native-path:          BAT0
  state:                fully-charged
  energy:               22.54 Wh
  energy-full:          25.01 Wh
  energy-rate:          0 W
  percentage:           90%
  charge-start-threshold:        75%
  charge-end-threshold:          80%
INFO
  exit 0
fi

exit 1
STUB
chmod +x "$dual_dir/bin/upower"

dual_output=$(OMARCHY_POWER_SUPPLY_PATH="$dual_dir/power" PATH="$dual_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'percentage\t23%' <<<"$dual_output" >/dev/null || fail "dual battery status uses combined energy percentage" "$dual_output"
grep -Fx $'state\tcharging' <<<"$dual_output" >/dev/null || fail "dual battery status is charging when any pack is taking current" "$dual_output"
grep -Fx $'rate\t3.6W' <<<"$dual_output" >/dev/null || fail "dual battery status sums live pack rates" "$dual_output"
grep -Fx $'size\t96Wh' <<<"$dual_output" >/dev/null || fail "dual battery status sums pack capacities" "$dual_output"
grep -Fx $'cycles\t7, 2' <<<"$dual_output" >/dev/null || fail "dual battery status lists both pack cycle counts" "$dual_output"
grep -Fx $'pack.0.state\tholding' <<<"$dual_output" >/dev/null || fail "dual battery status marks the capped pack as holding" "$dual_output"
grep -Fx $'pack.1.state\tcharging' <<<"$dual_output" >/dev/null || fail "dual battery status marks the charging pack" "$dual_output"
grep -Fx $'pack.1.percentage\t0%' <<<"$dual_output" >/dev/null || fail "dual battery status reports the empty pack percentage" "$dual_output"

pass "dual battery status aggregates packs and still shows each one"

hold_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir" "$dual_dir" "$hold_dir"' EXIT
mkdir -p "$hold_dir/bin" "$hold_dir/power/BAT0" "$hold_dir/power/BAT1" "$hold_dir/power/AC"
printf 'Mains\n' >"$hold_dir/power/AC/type"
printf '1\n' >"$hold_dir/power/AC/online"
printf '0\n' >"$hold_dir/power/BAT0/power_now"
printf '0\n' >"$hold_dir/power/BAT1/power_now"
cat >"$hold_dir/bin/upower" <<'STUB'
#!/bin/bash

if [[ $1 == "-e" ]]; then
  echo "/org/freedesktop/UPower/devices/battery_BAT0"
  echo "/org/freedesktop/UPower/devices/battery_BAT1"
  exit 0
fi

if [[ $1 == "-i" && $2 == *BAT1 ]]; then
  cat <<'INFO'
  native-path:          BAT1
  state:                pending-charge
  energy:               56.0 Wh
  energy-full:          71.04 Wh
  energy-rate:          0 W
  percentage:           79%
  charge-start-threshold:        75%
  charge-end-threshold:          80%
INFO
  exit 0
fi

if [[ $1 == "-i" ]]; then
  cat <<'INFO'
  native-path:          BAT0
  state:                fully-charged
  energy:               22.54 Wh
  energy-full:          25.01 Wh
  energy-rate:          0 W
  percentage:           90%
  charge-start-threshold:        75%
  charge-end-threshold:          80%
INFO
  exit 0
fi

exit 1
STUB
chmod +x "$hold_dir/bin/upower"

hold_output=$(OMARCHY_POWER_SUPPLY_PATH="$hold_dir/power" PATH="$hold_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)
grep -Fx $'state\tholding' <<<"$hold_output" >/dev/null || fail "dual battery status is holding when every pack is at rest on AC" "$hold_output"
grep -Fx $'percentage\t81%' <<<"$hold_output" >/dev/null || fail "dual battery holding state still uses combined energy" "$hold_output"

pass "dual battery status holds when both packs are at the charge cap"

if matches=$(rg -n 'omarchy-battery-(capacity|remaining|remaining-time)' "$ROOT/bin" "$ROOT/test" "$ROOT/shell" "$ROOT/docs"); then
  fail "battery status owns capacity and remaining calculations" "$matches"
fi

pass "removed per-field battery helpers stay gone"
