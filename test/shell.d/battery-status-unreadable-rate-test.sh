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

# Rebuild BAT0 from scratch per case so a leftover attribute cannot decide the
# next one. Values arrive as `attribute=contents`; an empty string writes an
# empty file, which is what bash captures from a read that fails.
battery_fixture() {
  local attribute

  rm -rf "$tmp_dir/power"
  mkdir -p "$tmp_dir/power/BAT0"

  for attribute in "$@"; do
    printf '%s' "${attribute#*=}" >"$tmp_dir/power/BAT0/${attribute%%=*}"
  done
}

battery_rate() {
  local output

  output=$(OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power" PATH="$tmp_dir/bin:$PATH" \
    "$ROOT/bin/omarchy-battery-status" --shell)

  awk -F'\t' '$1 == "rate" { print $2; exit }' <<<"$output"
}

assert_rate() {
  local expected="$1"
  local description="$2"
  local actual

  actual=$(battery_rate)
  [[ $actual == "$expected" ]] || fail "$description" "expected: $expected
actual:   $actual"
  pass "$description"
}

# The reported bug: the attribute is present and world-readable, but the read
# returns ENODEV and hands back an empty string. Reading an empty file gives
# bash the same empty string, so the fixture reproduces what the script sees.
battery_fixture "power_now=" "voltage_now=12000000"
assert_rate "7.3W" "unreadable power_now keeps UPower's energy-rate"

battery_fixture "power_now=No such device" "voltage_now=12000000"
assert_rate "7.3W" "non-numeric power_now keeps UPower's energy-rate"

# The same hole sits in the current_now/voltage_now fallback, where a failed
# read would multiply out to 0W just as quietly.
battery_fixture "current_now=" "voltage_now=12000000"
assert_rate "7.3W" "unreadable current_now keeps UPower's energy-rate"

# And the reason the sysfs override exists in the first place: where the
# kernel does answer, its instantaneous reading still wins over UPower's
# laggier figure.
battery_fixture "power_now=10800000" "voltage_now=12000000"
assert_rate "10.8W" "readable power_now still overrides UPower's energy-rate"

battery_fixture "current_now=900000" "voltage_now=12000000"
assert_rate "10.8W" "readable current_now still overrides UPower's energy-rate"
