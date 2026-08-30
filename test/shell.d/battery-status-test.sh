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

pass "battery status reports a single pack"

# A ThinkPad with an internal cell and a hot-swap slice: reading whichever pack
# enumerates first reports 5% and 22Wh on a machine that is actually at 11% of
# 46Wh, so the composite has to come from UPower's DisplayDevice.
multi_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir" "$multi_dir"' EXIT

mkdir -p "$multi_dir/bin"
mkdir -p "$multi_dir/power/BAT0" "$multi_dir/power/BAT1"
printf '0\n' >"$multi_dir/power/BAT0/power_now"
printf '6\n' >"$multi_dir/power/BAT0/cycle_count"
printf '20514000\n' >"$multi_dir/power/BAT1/power_now"
printf '12\n' >"$multi_dir/power/BAT1/cycle_count"
cat >"$multi_dir/bin/upower" <<'STUB'
#!/bin/bash

if [[ $1 == "-e" ]]; then
  echo "/org/freedesktop/UPower/devices/battery_BAT0"
  echo "/org/freedesktop/UPower/devices/battery_BAT1"
  exit 0
fi

if [[ $1 == "-i" ]]; then
  case "$2" in
    */DisplayDevice)
      cat <<'INFO'
  battery
    present:             yes
    state:               discharging
    energy:              5.06 Wh
    energy-full:         46.75 Wh
    energy-rate:         19.972 W
    charge-cycles:       N/A
    time to empty:       15.2 minutes
    percentage:          10.8235%
INFO
      exit 0
      ;;
    */battery_BAT0)
      cat <<'INFO'
  native-path:          BAT0
    state:               pending-charge
    energy:              1.23 Wh
    energy-full:         22.96 Wh
    energy-rate:         0 W
    charge-cycles:       6
    percentage:          5%
    charge-start-threshold:        75%
    charge-end-threshold:          80%
INFO
      exit 0
      ;;
    */battery_BAT1)
      cat <<'INFO'
  native-path:          BAT1
    state:               discharging
    energy:              3.89 Wh
    energy-full:         23.79 Wh
    energy-rate:         20.514 W
    charge-cycles:       12
    percentage:          16%
    charge-start-threshold:        75%
    charge-end-threshold:          80%
INFO
      exit 0
      ;;
  esac
fi

exit 1
STUB
chmod +x "$multi_dir/bin/upower"

multi_output=$(OMARCHY_POWER_SUPPLY_PATH="$multi_dir/power" PATH="$multi_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'percentage\t11%' <<<"$multi_output" >/dev/null || fail "battery status reports the composite percentage" "$multi_output"
grep -Fx $'size\t46Wh' <<<"$multi_output" >/dev/null || fail "battery status sums capacity across packs" "$multi_output"
grep -Fx $'rate\t20.5W' <<<"$multi_output" >/dev/null || fail "battery status sums draw across packs" "$multi_output"
grep -Fx $'time\t15m' <<<"$multi_output" >/dev/null || fail "battery status reports the composite runtime" "$multi_output"
grep -Fx $'cycles\t6 · 12' <<<"$multi_output" >/dev/null || fail "battery status reports every cycle count" "$multi_output"
grep -Fx $'threshold\t75-80%' <<<"$multi_output" >/dev/null || fail "battery status keeps charge thresholds off the composite device" "$multi_output"

grep -Fx $'batteries\t2' <<<"$multi_output" >/dev/null || fail "battery status counts the packs" "$multi_output"
grep -Fx $'battery.1.name\tBAT0' <<<"$multi_output" >/dev/null || fail "battery status names the first pack" "$multi_output"
grep -Fx $'battery.1.percentage\t5%' <<<"$multi_output" >/dev/null || fail "battery status breaks out the first pack" "$multi_output"
grep -Fx $'battery.1.rate\t0W' <<<"$multi_output" >/dev/null || fail "battery status reports an idle pack as drawing nothing" "$multi_output"
grep -Fx $'battery.1.cycles\t6' <<<"$multi_output" >/dev/null || fail "battery status breaks out per-pack cycles" "$multi_output"
grep -Fx $'battery.2.name\tBAT1' <<<"$multi_output" >/dev/null || fail "battery status names the second pack" "$multi_output"
grep -Fx $'battery.2.percentage\t16%' <<<"$multi_output" >/dev/null || fail "battery status breaks out the second pack" "$multi_output"
grep -Fx $'battery.2.rate\t20.5W' <<<"$multi_output" >/dev/null || fail "battery status breaks out per-pack draw" "$multi_output"
grep -Fx $'battery.2.size\t23Wh' <<<"$multi_output" >/dev/null || fail "battery status breaks out per-pack capacity" "$multi_output"

pass "battery status aggregates every pack in the machine"

if matches=$(rg -n 'omarchy-battery-(capacity|remaining|remaining-time)' "$ROOT/bin" "$ROOT/test" "$ROOT/shell" "$ROOT/docs"); then
  fail "battery status owns capacity and remaining calculations" "$matches"
fi

pass "battery status owns capacity and remaining calculations"
