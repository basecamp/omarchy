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

if matches=$(rg -n 'omarchy-battery-(capacity|remaining|remaining-time)' "$ROOT/bin" "$ROOT/test" "$ROOT/shell" "$ROOT/docs"); then
  fail "battery status owns capacity and remaining calculations" "$matches"
fi

pass "battery status owns capacity and remaining calculations"
