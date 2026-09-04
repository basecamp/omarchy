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

grep -Fx $'percentage\t50%' <<<"$shell_output" >/dev/null || fail "battery status reports energy-based percentage" "$shell_output"
grep -Fx $'state\tdischarging' <<<"$shell_output" >/dev/null || fail "battery status reports state"
grep -Fx $'rate\t10.8W' <<<"$shell_output" >/dev/null || fail "battery status reports live sysfs power rate"
grep -Fx $'size\t56.7Wh' <<<"$shell_output" >/dev/null || fail "battery status reports full capacity" "$shell_output"
grep -Fx $'time\t2h 37m' <<<"$shell_output" >/dev/null || fail "battery status reports remaining time from Wh/W" "$shell_output"

pass "battery status reports a single live pack"

# Dual-battery ThinkPad with a present-but-dead internal pack (0 V / 0 Wh)
# enumerated first. DisplayDevice would report ~49% because it still counts
# BAT0's energy-full; the CLI must follow the live slice instead.
rm -rf "$tmp_dir"
tmp_dir=$(mktemp -d)
mkdir -p "$tmp_dir/bin" "$tmp_dir/power/BAT0" "$tmp_dir/power/BAT1" "$tmp_dir/power/AC"
printf '0\n' >"$tmp_dir/power/BAT0/voltage_now"
printf '0\n' >"$tmp_dir/power/BAT0/power_now"
printf '0\n' >"$tmp_dir/power/BAT0/energy_now"
printf 'Mains\n' >"$tmp_dir/power/AC/type"
printf '1\n' >"$tmp_dir/power/AC/online"
printf '2169000\n' >"$tmp_dir/power/BAT1/power_now"
printf '12257000\n' >"$tmp_dir/power/BAT1/voltage_now"
printf '20430000\n' >"$tmp_dir/power/BAT1/energy_now"
printf '100\n' >"$tmp_dir/power/BAT1/charge_control_end_threshold"
printf '0\n' >"$tmp_dir/power/BAT1/charge_control_start_threshold"
cat >"$tmp_dir/bin/upower" <<'STUB'
#!/bin/bash

if [[ $1 == "-e" ]]; then
  echo "/org/freedesktop/UPower/devices/battery_BAT0"
  echo "/org/freedesktop/UPower/devices/battery_BAT1"
  exit 0
fi

if [[ $1 == "-i" && $2 == *BAT0 ]]; then
  cat <<'INFO'
  native-path:          BAT0
  state:                pending-charge
  energy:               0 Wh
  energy-full:          20.65 Wh
  energy-rate:          0 W
  percentage:           0%
  charge-start-threshold:        75%
  charge-end-threshold:          80%
INFO
  exit 0
fi

if [[ $1 == "-i" && $2 == *BAT1 ]]; then
  cat <<'INFO'
  native-path:          BAT1
  state:                charging
  energy:               20.43 Wh
  energy-full:          20.94 Wh
  energy-rate:          2.17 W
  time to full:         14.1 minutes
  percentage:           98%
  charge-start-threshold:        75%
  charge-end-threshold:          80%
INFO
  exit 0
fi

exit 1
STUB
chmod +x "$tmp_dir/bin/upower"

shell_output=$(OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power" PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'percentage\t98%' <<<"$shell_output" >/dev/null || fail "battery status ignores a dead first pack" "$shell_output"
grep -Fx $'state\tcharging' <<<"$shell_output" >/dev/null || fail "battery status does not treat a dead pending-charge pack as holding" "$shell_output"
grep -Fx $'rate\t2.2W' <<<"$shell_output" >/dev/null || fail "battery status reports the live pack's power" "$shell_output"
grep -Fx $'size\t20.9Wh' <<<"$shell_output" >/dev/null || fail "battery status reports live capacity, not dead+live energy-full" "$shell_output"
grep -Fx $'time\t14m' <<<"$shell_output" >/dev/null || fail "battery status reports the live pack's time to full" "$shell_output"
grep -Fx $'pack.0.path\tBAT1' <<<"$shell_output" >/dev/null || fail "battery status names the live pack for the panel" "$shell_output"
if grep -F $'pack.1.path' <<<"$shell_output" >/dev/null; then
  fail "battery status does not name a dead pack" "$shell_output"
fi
if grep -F $'threshold' <<<"$shell_output" >/dev/null; then
  fail "battery status omits a 0-100 kernel charge window" "$shell_output"
fi

pass "battery status ignores a present-but-dead pack"

# Signed sysfs power_now while UPower says charging must still yield a time.
printf -- '-2169000\n' >"$tmp_dir/power/BAT1/power_now"
shell_output=$(OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power" PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)
grep -Fx $'state\tcharging' <<<"$shell_output" >/dev/null || fail "signed charging rate keeps charging state" "$shell_output"
grep -Fx $'rate\t2.2W' <<<"$shell_output" >/dev/null || fail "signed charging rate is displayed absolute" "$shell_output"
grep -Fx $'time\t14m' <<<"$shell_output" >/dev/null || fail "signed charging rate still estimates time to full" "$shell_output"
pass "battery status estimates time from signed charging watts"

if matches=$(rg -n 'omarchy-battery-(capacity|remaining|remaining-time)' "$ROOT/bin" "$ROOT/test" "$ROOT/shell" "$ROOT/docs"); then
  fail "battery status owns capacity and remaining calculations" "$matches"
fi

pass "battery status owns capacity and remaining calculations"
