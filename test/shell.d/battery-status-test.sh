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

# The report is parsed in one pass rather than one awk per field. Count the awk
# invocations to keep it that way: quattro ran eleven, and the power panel
# re-reads this every five seconds while it is open.
awk_log="$tmp_dir/awk-calls"
mkdir -p "$tmp_dir/counting-bin"
real_awk=$(command -v awk)
cat >"$tmp_dir/counting-bin/awk" <<STUB
#!/bin/bash
printf 'awk\n' >>"$awk_log"
exec "$real_awk" "\$@"
STUB
chmod +x "$tmp_dir/counting-bin/awk"

: >"$awk_log"
OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power" PATH="$tmp_dir/counting-bin:$tmp_dir/bin:$PATH" \
  "$ROOT/bin/omarchy-battery-status" --shell >/dev/null
awk_calls=$(wc -l <"$awk_log")
(( awk_calls <= 6 )) || fail "the battery report is parsed without one process per field (awk ran $awk_calls times)"
pass "the battery report is parsed in one pass"

# Fields the single pass has to keep taking from the first line that matches,
# including the two that only some batteries report.
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
  energy-full:          56.7 Wh
  energy-rate:          7.3 W
  time to full:         45.0 minutes
  percentage:           88%
  charge-start-threshold: 70%
  charge-end-threshold: 90%
INFO
  exit 0
fi

exit 1
STUB

threshold_output=$(OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power" PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)
grep -Fx $'percentage\t88%' <<<"$threshold_output" >/dev/null || fail "battery status still reads percentage past the threshold lines"
grep -Fx $'time\t45m' <<<"$threshold_output" >/dev/null || fail "battery status still formats a time given in minutes"
grep -Fx $'state\tcharging' <<<"$threshold_output" >/dev/null || fail "battery status still reads charging state"
pass "battery status reads a report carrying charge thresholds"
