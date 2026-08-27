#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin" "$tmp_dir/devices"

cat >"$tmp_dir/bin/upower" <<'STUB'
#!/bin/bash
[[ $1 == "-e" ]] || exit 1
cat "$UPOWER_DEVICES_FILE"
STUB

cat >"$tmp_dir/bin/busctl" <<'STUB'
#!/bin/bash
if [[ $1 == "get-property" ]]; then
  value=$(<"$BATTERY_FIXTURE_DIR/${3##*/}/$5") || exit 1
  case "$5" in
    ChargeThresholdSupported | ChargeThresholdEnabled) printf 'b %s\n' "$value" ;;
    *) printf 'u %s\n' "$value" ;;
  esac
elif [[ $1 == "call" ]]; then
  printf '%s\t%s\n' "$3" "$7" >>"$BATTERY_CALL_LOG"
else
  exit 1
fi
STUB

chmod +x "$tmp_dir/bin/upower" "$tmp_dir/bin/busctl"
export PATH="$tmp_dir/bin:$ROOT/bin:$PATH"
export UPOWER_DEVICES_FILE="$tmp_dir/upower-devices"
export BATTERY_FIXTURE_DIR="$tmp_dir/devices"
export BATTERY_CALL_LOG="$tmp_dir/calls"

reset_fixture() {
  rm -rf "$BATTERY_FIXTURE_DIR"
  mkdir -p "$BATTERY_FIXTURE_DIR"
  : >"$UPOWER_DEVICES_FILE"
  : >"$BATTERY_CALL_LOG"
}

add_battery() {
  local name="$1" supported="$2" enabled="$3" settings="$4" start="$5" end="$6"
  local fixture="$BATTERY_FIXTURE_DIR/$name"

  mkdir -p "$fixture"
  printf '/org/freedesktop/UPower/devices/%s\n' "$name" >>"$UPOWER_DEVICES_FILE"
  printf '%s\n' "$supported" >"$fixture/ChargeThresholdSupported"
  printf '%s\n' "$enabled" >"$fixture/ChargeThresholdEnabled"
  printf '%s\n' "$settings" >"$fixture/ChargeThresholdSettingsSupported"
  printf '%s\n' "$start" >"$fixture/ChargeStartThreshold"
  printf '%s\n' "$end" >"$fixture/ChargeEndThreshold"
}

field() {
  awk -F '\t' -v key="$2" '$1 == key { print $2; exit }' <<<"$1"
}

reset_fixture
output=$(omarchy-battery-limit status --shell)
[[ $(field "$output" state) == unsupported ]] || fail "battery limit hides unsupported hardware"
pass "battery limit hides unsupported hardware"

reset_fixture
add_battery battery_BAT0 true false 2 75 80
output=$(omarchy-battery-limit status --shell)
[[ $(field "$output" state) == disabled ]] || fail "battery limit reports disabled state"
[[ $(field "$output" policy) == 80 ]] || fail "battery limit reports the UPower policy"
omarchy-battery-limit enable >/dev/null
grep -Fx $'/org/freedesktop/UPower/devices/battery_BAT0\ttrue' "$BATTERY_CALL_LOG" >/dev/null ||
  fail "battery limit enables through UPower"
pass "battery limit enables through UPower"

reset_fixture
add_battery battery_BAT0 true true 3 75 80
add_battery battery_BAT1 true false 2 75 85
output=$(omarchy-battery-limit status --shell)
[[ $(field "$output" state) == disabled ]] || fail "battery limit leaves a partial set unchecked"
omarchy-battery-limit disable >/dev/null
[[ $(wc -l <"$BATTERY_CALL_LOG") == 2 ]] || fail "battery limit updates every supported battery"
grep -F $'\tfalse' "$BATTERY_CALL_LOG" >/dev/null || fail "battery limit disables through UPower"
pass "battery limit updates every supported battery"

if rg -i 'asus|asusctl|pkexec|systemctl|charge_control_' "$ROOT/bin/omarchy-battery-limit" >/dev/null; then
  fail "battery limit remains vendor-neutral and delegates privileges to UPower"
fi
pass "battery limit uses only the vendor-neutral UPower primitive"
