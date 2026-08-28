#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
dual_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir" "$dual_dir"' EXIT

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

# A machine with two batteries has to report its own charge, state and runtime,
# not the first cell's. BAT0 is left at current_now=0 on purpose: a ThinkPad
# drains the external pack first, so a draw read from one cell reports 0W while
# the laptop is discharging. It is fully-charged for the same reason — the cell
# the kernel enumerates first is the one still holding its charge, and reading
# state from it reports a discharging laptop as holding.
mkdir -p "$dual_dir/bin"
mkdir -p "$dual_dir/power/BAT0" "$dual_dir/power/BAT1"
printf '0\n' >"$dual_dir/power/BAT0/current_now"
printf '12000000\n' >"$dual_dir/power/BAT0/voltage_now"
printf '500000\n' >"$dual_dir/power/BAT1/current_now"
printf '12000000\n' >"$dual_dir/power/BAT1/voltage_now"
cat >"$dual_dir/bin/upower" <<'STUB'
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
  state:                discharging
  energy-full:          48.0 Wh
  energy-rate:          6.0 W
  time to empty:        3.0 hours
  percentage:           53%
INFO
    ;;
  */battery_BAT1)
    cat <<'INFO'
  native-path:          BAT1
  state:                discharging
  percentage:           95%
INFO
    ;;
  *)
    cat <<'INFO'
  native-path:          BAT0
  state:                fully-charged
  percentage:           21%
INFO
    ;;
  esac
  exit 0
fi

exit 1
STUB
chmod +x "$dual_dir/bin/upower"

dual_output=$(OMARCHY_POWER_SUPPLY_PATH="$dual_dir/power" PATH="$dual_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'percentage\t53%' <<<"$dual_output" >/dev/null || fail "battery status reports the machine percentage, not the first cell"
grep -Fx $'state\tdischarging' <<<"$dual_output" >/dev/null || fail "battery status reports the machine state, not the first cell"
grep -Fx $'time\t3h' <<<"$dual_output" >/dev/null || fail "battery status reports the machine remaining time"
grep -Fx $'size\t48Wh' <<<"$dual_output" >/dev/null || fail "battery status reports the combined capacity"
grep -Fx $'rate\t6W' <<<"$dual_output" >/dev/null || fail "battery status sums power draw across batteries"

if matches=$(rg -n 'omarchy-battery-(capacity|remaining|remaining-time)' "$ROOT/bin" "$ROOT/test" "$ROOT/shell" "$ROOT/docs"); then
  fail "battery status owns capacity and remaining calculations" "$matches"
fi

pass "battery status owns capacity and remaining calculations"
