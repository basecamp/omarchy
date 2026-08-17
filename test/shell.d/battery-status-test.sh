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
grep -Fx $'time\t2h 37m' <<<"$shell_output" >/dev/null || fail "battery status reports remaining time"

# A pack held at a charge threshold keeps reporting pending-charge with a 0W
# rate for tens of seconds after it starts charging again, so a stale label must
# not win over sysfs and report holding mid-charge.
stale_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir" "$stale_dir"' EXIT

mkdir -p "$stale_dir/bin" "$stale_dir/power/BAT0" "$stale_dir/power/AC"
printf '29000000\n' >"$stale_dir/power/BAT0/power_now"
printf 'Charging\n' >"$stale_dir/power/BAT0/status"
printf '80\n' >"$stale_dir/power/BAT0/charge_control_end_threshold"
printf 'Mains\n' >"$stale_dir/power/AC/type"
printf '1\n' >"$stale_dir/power/AC/online"
cat >"$stale_dir/bin/upower" <<'STUB'
#!/bin/bash

if [[ $1 == "-e" ]]; then
  echo "/org/freedesktop/UPower/devices/battery_BAT0"
  exit 0
fi

if [[ $1 == "-i" ]]; then
  cat <<'INFO'
  native-path:          BAT0
  state:                pending-charge
  energy:               42.5 Wh
  energy-full:          56.7 Wh
  energy-rate:          0 W
  percentage:           75%
INFO
  exit 0
fi

exit 1
STUB
chmod +x "$stale_dir/bin/upower"

stale_output=$(OMARCHY_POWER_SUPPLY_PATH="$stale_dir/power" PATH="$stale_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'state\tcharging' <<<"$stale_output" >/dev/null || fail "battery status trusts sysfs over a stale upower state" "$stale_output"
grep -Fx $'rate\t29W' <<<"$stale_output" >/dev/null || fail "battery status reports the live charge rate" "$stale_output"

# The same battery parked at its threshold, drawing nothing, is genuinely holding.
printf '0\n' >"$stale_dir/power/BAT0/power_now"
printf 'Not charging\n' >"$stale_dir/power/BAT0/status"

holding_output=$(OMARCHY_POWER_SUPPLY_PATH="$stale_dir/power" PATH="$stale_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'state\tholding' <<<"$holding_output" >/dev/null || fail "battery status reports holding once the battery stops drawing" "$holding_output"

# Multi-battery laptops (ThinkPad T480 and friends) expose one BAT device per
# pack; every reading has to combine them instead of following upower's first.
dual_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir" "$stale_dir" "$dual_dir"' EXIT

mkdir -p "$dual_dir/bin" "$dual_dir/power/BAT0" "$dual_dir/power/BAT1"
printf '0\n' >"$dual_dir/power/BAT0/power_now"
printf '8000000\n' >"$dual_dir/power/BAT1/power_now"
cat >"$dual_dir/bin/upower" <<'STUB'
#!/bin/bash

if [[ $1 == "-e" ]]; then
  echo "/org/freedesktop/UPower/devices/battery_BAT0"
  echo "/org/freedesktop/UPower/devices/battery_BAT1"
  exit 0
fi

if [[ $1 == "-i" && $2 == *BAT0 ]]; then
  cat <<'INFO'
  native-path:          BAT0
  present:              yes
  state:                discharging
  energy:               13.3 Wh
  energy-full:          16.7 Wh
  energy-rate:          0 W
  charge-cycles:        348
  percentage:           80%
INFO
  exit 0
fi

if [[ $1 == "-i" && $2 == *BAT1 ]]; then
  cat <<'INFO'
  native-path:          BAT1
  present:              yes
  state:                discharging
  energy:               57.4 Wh
  energy-full:          71.0 Wh
  energy-rate:          8 W
  charge-cycles:        82
  percentage:           81%
INFO
  exit 0
fi

exit 1
STUB
chmod +x "$dual_dir/bin/upower"

dual_output=$(OMARCHY_POWER_SUPPLY_PATH="$dual_dir/power" PATH="$dual_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'percentage\t81%' <<<"$dual_output" >/dev/null || fail "battery status blends both packs into one percentage" "$dual_output"
grep -Fx $'size\t87Wh' <<<"$dual_output" >/dev/null || fail "battery status sums capacity across packs" "$dual_output"
grep -Fx $'rate\t8W' <<<"$dual_output" >/dev/null || fail "battery status sums power draw across packs" "$dual_output"
grep -Fx $'time\t8h 50m' <<<"$dual_output" >/dev/null || fail "battery status spends both packs before empty" "$dual_output"
grep -Fx $'cycles\t348 / 82' <<<"$dual_output" >/dev/null || fail "battery status lists cycles per pack" "$dual_output"
grep -Fx $'batteries\t2' <<<"$dual_output" >/dev/null || fail "battery status reports the pack count" "$dual_output"
grep -Fx $'battery1\t16Wh · 80%' <<<"$dual_output" >/dev/null || fail "battery status breaks out the first pack" "$dual_output"
grep -Fx $'battery2\t71Wh · 81%' <<<"$dual_output" >/dev/null || fail "battery status breaks out the second pack" "$dual_output"

grep -q '^battery1' <<<"$shell_output" && fail "battery status omits the breakdown on single-battery machines" "$shell_output"

# One pack parked at its threshold while the other still charges is charging,
# not holding: the combined rate decides, not the parked pack's label.
printf 'Not charging\n' >"$dual_dir/power/BAT0/status"
printf 'Charging\n' >"$dual_dir/power/BAT1/status"
printf '29000000\n' >"$dual_dir/power/BAT1/power_now"
printf '80\n' >"$dual_dir/power/BAT0/charge_control_end_threshold"
mkdir -p "$dual_dir/power/AC"
printf 'Mains\n' >"$dual_dir/power/AC/type"
printf '1\n' >"$dual_dir/power/AC/online"

mixed_output=$(OMARCHY_POWER_SUPPLY_PATH="$dual_dir/power" PATH="$dual_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'state\tcharging' <<<"$mixed_output" >/dev/null || fail "battery status charges while one pack sits at its threshold" "$mixed_output"
grep -Fx $'rate\t29W' <<<"$mixed_output" >/dev/null || fail "battery status reports the charging pack's rate" "$mixed_output"

if matches=$(rg -n 'omarchy-battery-(capacity|remaining|remaining-time)' "$ROOT/bin" "$ROOT/test" "$ROOT/shell" "$ROOT/docs"); then
  fail "battery status owns capacity and remaining calculations" "$matches"
fi

pass "battery status owns capacity and remaining calculations"
