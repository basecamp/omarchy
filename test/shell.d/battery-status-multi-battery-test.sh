#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

# Reproduces a dual-battery laptop (e.g. a ThinkPad with a Power Bridge bay):
# BAT0 reports near-zero upower fields, BAT1 is the real battery. upower's
# DisplayDevice correctly aggregates both into one reading; a naive "first
# BAT* device" read does not, and lands on BAT0's zeroes instead.
#
# The sysfs telemetry deliberately gives BOTH batteries distinguishable
# nonzero values: BAT0 draws 4.2W with 12 cycles, BAT1 draws 10.8W with 347
# cycles. That way the assertions below can tell summing every device (15W)
# apart from picking just one (4.2W or 10.8W), and the max cycle count (347)
# apart from the first enumerated one (12).
mkdir -p "$tmp_dir/bin"
mkdir -p "$tmp_dir/power/BAT0"
mkdir -p "$tmp_dir/power/BAT1"
printf '4200000\n' >"$tmp_dir/power/BAT0/power_now"
printf '12\n' >"$tmp_dir/power/BAT0/cycle_count"
printf '900000\n' >"$tmp_dir/power/BAT1/current_now"
printf '12000000\n' >"$tmp_dir/power/BAT1/voltage_now"
printf '347\n' >"$tmp_dir/power/BAT1/cycle_count"

cat >"$tmp_dir/bin/upower" <<'STUB'
#!/bin/bash

if [[ $1 == "-e" ]]; then
  echo "/org/freedesktop/UPower/devices/battery_BAT0"
  echo "/org/freedesktop/UPower/devices/battery_BAT1"
  exit 0
fi

if [[ $1 == "-i" && $2 == *DisplayDevice ]]; then
  cat <<'INFO'
  present:              yes
  state:                discharging
  energy:               20.16 Wh
  energy-full:          22.09 Wh
  energy-rate:          5.573 W
  time to empty:        3.6 hours
  percentage:           91.2177%
INFO
  exit 0
fi

if [[ $1 == "-i" && $2 == *BAT0 ]]; then
  cat <<'INFO'
  native-path:          BAT0
  present:              yes
  state:                not-charging
  energy:               0 Wh
  energy-full:          0 Wh
  energy-rate:          0 W
  percentage:           0%
  charge-start-threshold: 75%
  charge-end-threshold:   80%
INFO
  exit 0
fi

if [[ $1 == "-i" && $2 == *BAT1 ]]; then
  cat <<'INFO'
  native-path:          BAT1
  present:              yes
  state:                discharging
  energy:               20.16 Wh
  energy-full:          22.09 Wh
  energy-rate:          5.573 W
  time to empty:        3.6 hours
  percentage:           91.2177%
  charge-start-threshold: 75%
  charge-end-threshold:   80%
INFO
  exit 0
fi

exit 1
STUB
chmod +x "$tmp_dir/bin/upower"

shell_output=$(OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power" PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'percentage\t91%' <<<"$shell_output" >/dev/null || fail "multi-battery status reports the aggregate percentage, not BAT0's 0%" "$shell_output"
grep -Fx $'state\tdischarging' <<<"$shell_output" >/dev/null || fail "multi-battery status reports the aggregate state, not BAT0's not-charging" "$shell_output"
grep -Fx $'size\t22Wh' <<<"$shell_output" >/dev/null || fail "multi-battery status reports the aggregate capacity, not BAT0's 0Wh" "$shell_output"
grep -Fx $'rate\t15W' <<<"$shell_output" >/dev/null || fail "multi-battery status sums live sysfs wattage across every battery, not just one device's" "$shell_output"
grep -Fx $'cycles\t347' <<<"$shell_output" >/dev/null || fail "multi-battery status reports the highest cycle count, not the first enumerated one" "$shell_output"
grep -Fx $'threshold\t75-80%' <<<"$shell_output" >/dev/null || fail "multi-battery status still reports the charge threshold" "$shell_output"

pass "multi-battery status reports the aggregate battery, not the first enumerated one"
