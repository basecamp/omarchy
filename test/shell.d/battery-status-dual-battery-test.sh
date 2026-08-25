#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

# A dual-battery ThinkPad whose internal pack (BAT0) is dead: zero full-charge
# capacity, no cycle count, enumerated first by UPower. The removable pack
# (BAT1) is the one actually powering the machine.
mkdir -p "$tmp_dir/bin"
mkdir -p "$tmp_dir/power/BAT0" "$tmp_dir/power/BAT1"

printf 'Battery\n' >"$tmp_dir/power/BAT0/type"
printf '1\n' >"$tmp_dir/power/BAT0/present"
printf '0\n' >"$tmp_dir/power/BAT0/energy_full"
printf '%s\n' -1 >"$tmp_dir/power/BAT0/cycle_count"
printf '0\n' >"$tmp_dir/power/BAT0/power_now"

printf 'Battery\n' >"$tmp_dir/power/BAT1/type"
printf '1\n' >"$tmp_dir/power/BAT1/present"
printf '46530000\n' >"$tmp_dir/power/BAT1/energy_full"
printf '5\n' >"$tmp_dir/power/BAT1/cycle_count"
printf '30500000\n' >"$tmp_dir/power/BAT1/power_now"

# A wireless mouse also reports type Battery, but its scope marks it as a
# peripheral: it must not leak into the machine's wattage or cycle counts.
mkdir -p "$tmp_dir/power/hidpp_battery_0"
printf 'Battery\n' >"$tmp_dir/power/hidpp_battery_0/type"
printf 'Device\n' >"$tmp_dir/power/hidpp_battery_0/scope"
printf '1000000\n' >"$tmp_dir/power/hidpp_battery_0/power_now"
printf '99\n' >"$tmp_dir/power/hidpp_battery_0/cycle_count"

cat >"$tmp_dir/bin/upower" <<'STUB'
#!/bin/bash

if [[ $1 == "-e" ]]; then
  echo "/org/freedesktop/UPower/devices/battery_BAT0"
  echo "/org/freedesktop/UPower/devices/battery_BAT1"
  exit 0
fi

if [[ $1 == "-i" && $2 == "/org/freedesktop/UPower/devices/DisplayDevice" ]]; then
  cat <<'INFO'
  state:                charging
  energy:               27.3 Wh
  energy-full:          46.5 Wh
  energy-rate:          30.9 W
  time to full:         1.2 hours
  percentage:           58%
INFO
  exit 0
fi

if [[ $1 == "-i" && $2 == "/org/freedesktop/UPower/devices/battery_BAT0" ]]; then
  cat <<'INFO'
  native-path:          BAT0
  state:                pending-charge
  energy:               0 Wh
  energy-full:          0 Wh
  energy-rate:          0 W
  percentage:           0%
  charge-start-threshold: 75%
  charge-end-threshold: 80%
INFO
  exit 0
fi

exit 1
STUB
chmod +x "$tmp_dir/bin/upower"

shell_output=$(OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power" PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'percentage\t58%' <<<"$shell_output" >/dev/null || fail "dual battery reports the aggregate percentage, not the dead pack's 0%" "$shell_output"
grep -Fx $'state\tcharging' <<<"$shell_output" >/dev/null || fail "dual battery reports the aggregate state, not the dead pack's pending-charge" "$shell_output"
grep -Fx $'rate\t30.5W' <<<"$shell_output" >/dev/null || fail "dual battery sums live sysfs wattage over packs that hold a charge" "$shell_output"
grep -Fx $'size\t46Wh' <<<"$shell_output" >/dev/null || fail "dual battery reports the aggregate capacity, not the dead pack's 0Wh" "$shell_output"
grep -Fx $'cycles\t5' <<<"$shell_output" >/dev/null || fail "dual battery reports the live pack's cycle count, not the dead pack's" "$shell_output"
grep -Fx $'threshold\t75-80%' <<<"$shell_output" >/dev/null || fail "threshold still comes from the first battery's UPower info" "$shell_output"

pass "dual-battery machine with a dead pack reports the working battery"

# Both packs alive: wattage is the combined draw and each pack contributes
# its own cycle count, in sysfs order.
mkdir -p "$tmp_dir/power2/BAT0" "$tmp_dir/power2/BAT1"

printf 'Battery\n' >"$tmp_dir/power2/BAT0/type"
printf '1\n' >"$tmp_dir/power2/BAT0/present"
printf '23800000\n' >"$tmp_dir/power2/BAT0/energy_full"
printf '7\n' >"$tmp_dir/power2/BAT0/cycle_count"
printf '12000000\n' >"$tmp_dir/power2/BAT0/power_now"

printf 'Battery\n' >"$tmp_dir/power2/BAT1/type"
printf '1\n' >"$tmp_dir/power2/BAT1/present"
printf '46530000\n' >"$tmp_dir/power2/BAT1/energy_full"
printf '12600000\n' >"$tmp_dir/power2/BAT1/voltage_now"
printf '5\n' >"$tmp_dir/power2/BAT1/cycle_count"
printf '18500000\n' >"$tmp_dir/power2/BAT1/power_now"

shell_output=$(OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power2" PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'rate\t30.5W' <<<"$shell_output" >/dev/null || fail "two live packs report their combined sysfs wattage" "$shell_output"
grep -Fx $'cycles\t7 / 5' <<<"$shell_output" >/dev/null || fail "two live packs report both cycle counts in sysfs order" "$shell_output"

pass "dual-battery machine with two live packs sums wattage and lists both cycle counts"

# A pack without sysfs power telemetry would make the sum a partial total, so
# the rate falls back to UPower's aggregate instead.
rm "$tmp_dir/power2/BAT1/power_now"

shell_output=$(OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power2" PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'rate\t30.9W' <<<"$shell_output" >/dev/null || fail "an unmetered pack falls back to the aggregate rate instead of a partial sum" "$shell_output"

pass "a pack without power telemetry falls back to UPower's aggregate rate"

# Some ACPI firmware fails the read() on a present telemetry attribute with
# ENODEV, yielding an empty string rather than a missing file. Neither an
# empty power_now nor an empty current_now may be coerced into a metered 0W
# (basecamp/omarchy#6895).
: >"$tmp_dir/power2/BAT1/power_now"

shell_output=$(OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power2" PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'rate\t30.9W' <<<"$shell_output" >/dev/null || fail "an empty power_now read falls back to the aggregate rate instead of 0W" "$shell_output"

pass "an empty power_now read falls back to UPower's aggregate rate"

rm "$tmp_dir/power2/BAT1/power_now"
: >"$tmp_dir/power2/BAT1/current_now"

shell_output=$(OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power2" PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'rate\t30.9W' <<<"$shell_output" >/dev/null || fail "an empty current_now read falls back to the aggregate rate instead of 0W" "$shell_output"

pass "an empty current_now read falls back to UPower's aggregate rate"

# UPower's composite DisplayDevice keeps a dead pack's advertised energy-full
# in the percentage denominator: a 20.65Wh corpse next to a 20.94Wh live pack
# near full reads as 49% with a ten-hour charge (#7916). The headline figures
# must follow the packs that actually hold a charge — and a dead pack still
# advertising its old energy_full must not count as alive.
mkdir -p "$tmp_dir/power3/BAT0" "$tmp_dir/power3/BAT1" "$tmp_dir/bin3"

printf 'Battery\n' >"$tmp_dir/power3/BAT0/type"
printf '1\n' >"$tmp_dir/power3/BAT0/present"
printf '0\n' >"$tmp_dir/power3/BAT0/voltage_now"
printf '0\n' >"$tmp_dir/power3/BAT0/energy_now"
printf '20650000\n' >"$tmp_dir/power3/BAT0/energy_full"
printf '0\n' >"$tmp_dir/power3/BAT0/power_now"

printf 'Battery\n' >"$tmp_dir/power3/BAT1/type"
printf '1\n' >"$tmp_dir/power3/BAT1/present"
printf '12300000\n' >"$tmp_dir/power3/BAT1/voltage_now"
printf '20400000\n' >"$tmp_dir/power3/BAT1/energy_now"
printf '20940000\n' >"$tmp_dir/power3/BAT1/energy_full"
printf '2200000\n' >"$tmp_dir/power3/BAT1/power_now"

cat >"$tmp_dir/bin3/upower" <<'STUB'
#!/bin/bash

if [[ $1 == "-e" ]]; then
  echo "/org/freedesktop/UPower/devices/battery_BAT0"
  echo "/org/freedesktop/UPower/devices/battery_BAT1"
  exit 0
fi

if [[ $1 == "-i" && $2 == "/org/freedesktop/UPower/devices/DisplayDevice" ]]; then
  cat <<'INFO'
  state:                charging
  energy:               20.4 Wh
  energy-full:          41.59 Wh
  energy-rate:          2.2 W
  time to full:         9.6 hours
  percentage:           49%
INFO
  exit 0
fi

if [[ $1 == "-i" ]]; then
  cat <<'INFO'
  native-path:          BAT0
  state:                pending-charge
  percentage:           0%
INFO
  exit 0
fi

exit 1
STUB
chmod +x "$tmp_dir/bin3/upower"

shell_output=$(OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power3" PATH="$tmp_dir/bin3:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'percentage\t97%' <<<"$shell_output" >/dev/null || fail "a dead pack's energy-full stays out of the percentage denominator" "$shell_output"
grep -Fx $'state\tcharging' <<<"$shell_output" >/dev/null || fail "the live pack's charging state survives a dead sibling" "$shell_output"
grep -Fx $'rate\t2.2W' <<<"$shell_output" >/dev/null || fail "the rate reflects the live pack's draw" "$shell_output"
grep -Fx $'size\t20Wh' <<<"$shell_output" >/dev/null || fail "capacity counts only packs that hold a charge" "$shell_output"
grep -Fx $'time\t14m' <<<"$shell_output" >/dev/null || fail "time to full is not stretched by a dead pack's capacity" "$shell_output"

pass "a dead pack's advertised capacity does not drag down the headline figures"
