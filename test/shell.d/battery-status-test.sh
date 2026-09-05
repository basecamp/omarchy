#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
cat >"$tmp_dir/bin/upower" <<'STUB'
#!/bin/bash

if [[ $1 == "-e" ]]; then
  echo "/org/freedesktop/UPower/devices/battery_BAT0"
  exit 0
fi

if [[ $1 == "-i" ]]; then
  cat "${UPOWER_INFO:?}"
  exit 0
fi

exit 1
STUB
chmod +x "$tmp_dir/bin/upower"

setup_battery() {
  local state=$1 percentage=$2 start=$3 end=$4
  rm -rf "$tmp_dir/power"
  mkdir -p "$tmp_dir/power/BAT0" "$tmp_dir/power/AC"
  printf '900000\n' >"$tmp_dir/power/BAT0/current_now"
  printf '12000000\n' >"$tmp_dir/power/BAT0/voltage_now"
  printf 'Mains\n' >"$tmp_dir/power/AC/type"
  printf '1\n' >"$tmp_dir/power/AC/online"
  [[ -n $start ]] && printf '%s\n' "$start" >"$tmp_dir/power/BAT0/charge_control_start_threshold"
  [[ -n $end ]] && printf '%s\n' "$end" >"$tmp_dir/power/BAT0/charge_control_end_threshold"
  UPOWER_INFO="$tmp_dir/info"
  cat >"$UPOWER_INFO" <<INFO
  native-path:          BAT0
  state:                $state
  energy:               28.3 Wh
  energy-full:          56.7 Wh
  energy-rate:          7.3 W
  time to empty:        2.5 hours
  percentage:           $percentage%
INFO
  export UPOWER_INFO
}

run_shell() {
  OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power" PATH="$tmp_dir/bin:$PATH" \
    "$ROOT/bin/omarchy-battery-status" --shell
}

setup_battery discharging 51 "" ""
shell_output=$(run_shell)

grep -Fx $'percentage\t51%' <<<"$shell_output" >/dev/null || fail "battery status reports percentage"
grep -Fx $'state\tdischarging' <<<"$shell_output" >/dev/null || fail "battery status reports state"
grep -Fx $'rate\t10.8W' <<<"$shell_output" >/dev/null || fail "battery status reports live sysfs power rate"
grep -Fx $'size\t56Wh' <<<"$shell_output" >/dev/null || fail "battery status reports full capacity"
grep -Fx $'time\t2h 30m' <<<"$shell_output" >/dev/null || fail "battery status reports remaining time"

# A dead pack parked in pending-charge with kernel-default limits (0/100) must
# not read as a threshold hold.
setup_battery pending-charge 0 "0" "100"
shell_output=$(run_shell)
grep -Fx $'state\tpending-charge' <<<"$shell_output" >/dev/null || fail "default-limit pending charge keeps its raw state"

grep -Fx $'threshold_start\t0' <<<"$shell_output" >/dev/null || fail "default limits are still reported"
grep -Fx $'threshold_end\t100' <<<"$shell_output" >/dev/null || fail "default limits are still reported"

if matches=$(rg -n '^state\tholding$' <<<"$shell_output"); then
  fail "kernel-default limits do not turn pending charge into a hold" "$matches"
fi

# A configured band reports as holding while inside it, and exposes the raw
# limits for the panel's own hold logic.
setup_battery pending-charge 78 "75" "80"
shell_output=$(run_shell)
grep -Fx $'state\tholding' <<<"$shell_output" >/dev/null || fail "in-band pending charge reports as holding"
grep -Fx $'threshold_start\t75' <<<"$shell_output" >/dev/null || fail "shell output exposes the limit start"
grep -Fx $'threshold_end\t80' <<<"$shell_output" >/dev/null || fail "shell output exposes the limit end"
grep -Fx $'threshold\t75-80%' <<<"$shell_output" >/dev/null || fail "threshold label spans the band"

# Above the band the hold no longer applies even though the state persists.
setup_battery pending-charge 90 "75" "80"
shell_output=$(run_shell)
if matches=$(rg -n '^state\tholding$' <<<"$shell_output"); then
  fail "out-of-band pending charge does not report as holding" "$matches"
fi

if matches=$(rg -n 'omarchy-battery-(capacity|remaining|remaining-time)' "$ROOT/bin" "$ROOT/test" "$ROOT/shell" "$ROOT/docs"); then
  fail "battery status owns capacity and remaining calculations" "$matches"
fi

pass "battery status owns capacity and remaining calculations"
pass "battery status distinguishes real holds from generic pending charge"
