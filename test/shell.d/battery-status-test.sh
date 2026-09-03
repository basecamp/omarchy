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

# Kernel charge registers beat a stuck UPower energy-full (MacBook SBS blip).
mkdir -p "$tmp_dir/power-mac/BAT0"
printf '6833000\n' >"$tmp_dir/power-mac/BAT0/charge_now"
printf '6876000\n' >"$tmp_dir/power-mac/BAT0/charge_full"
printf '7600000\n' >"$tmp_dir/power-mac/BAT0/voltage_min_design"
printf '8533000\n' >"$tmp_dir/power-mac/BAT0/voltage_now"
printf '0\n' >"$tmp_dir/power-mac/BAT0/current_now"
printf 'Full\n' >"$tmp_dir/power-mac/BAT0/status"
printf '274\n' >"$tmp_dir/power-mac/BAT0/cycle_count"
cat >"$tmp_dir/bin/upower" <<'STUB'
#!/bin/bash

if [[ $1 == "-e" ]]; then
  echo "/org/freedesktop/UPower/devices/battery_BAT0"
  exit 0
fi

if [[ $1 == "-i" ]]; then
  cat <<'INFO'
  native-path:          BAT0
  state:                charging
  energy:               51.4 Wh
  energy-full:          484.515 Wh
  energy-full-design:   54.34 Wh
  energy-rate:          3.2 W
  time to full:         5.6 days
  percentage:           10.6099%
INFO
  exit 0
fi

exit 1
STUB
chmod +x "$tmp_dir/bin/upower"

mac_output=$(OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power-mac" PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'percentage\t99%' <<<"$mac_output" >/dev/null || fail "battery status prefers sysfs charge percentage over stuck UPower" "$mac_output"
grep -Fx $'state\tfully-charged' <<<"$mac_output" >/dev/null || fail "battery status prefers kernel Full status over UPower charging" "$mac_output"
grep -Fx $'size\t52Wh' <<<"$mac_output" >/dev/null || fail "battery status reports sysfs pack size not stuck energy-full" "$mac_output"
grep -Fx $'cycles\t274' <<<"$mac_output" >/dev/null || fail "battery status still reports cycle count" "$mac_output"

pass "battery status owns capacity and remaining calculations"
