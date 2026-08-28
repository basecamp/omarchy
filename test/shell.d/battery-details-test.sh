#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

# Each scenario is a directory holding a device list, one canned `upower -i`
# dump per device, and the DMI product string the machine would report.
new_machine() {
  local name="$1"
  local product="${2:-}"

  scenario="$tmp_dir/$name"
  mkdir -p "$scenario/bin" "$scenario/dmi" "$scenario/power"
  : >"$scenario/devices"
  [[ -n $product ]] && printf '%s\n' "$product" >"$scenario/dmi/product_version"

  cat >"$scenario/bin/upower" <<'STUB'
#!/bin/bash

if [[ $1 == "-e" ]]; then
  cat "$STUB_DIR/devices"
  exit 0
fi

if [[ $1 == "-i" ]]; then
  cat "$STUB_DIR/${2##*/}" 2>/dev/null
  exit 0
fi

exit 1
STUB
  chmod +x "$scenario/bin/upower"
}

add_device() {
  local device="$1"

  printf '/org/freedesktop/UPower/devices/%s\n' "$device" >>"$scenario/devices"
  cat >"$scenario/$device"
}

run_details() {
  STUB_DIR="$scenario" \
    OMARCHY_DMI_PATH="$scenario/dmi" \
    OMARCHY_POWER_SUPPLY_PATH="$scenario/power" \
    PATH="$scenario/bin:$PATH" \
    "$ROOT/bin/omarchy-battery-details"
}

# A Power Bridge ThinkPad names its cells, and a paired mouse is not one of
# them: UPower enumerates peripherals under the same battery_ prefix, so the
# prefix alone is not a filter.
new_machine power_bridge "ThinkPad T480 W0A"
add_device battery_BAT0 <<'INFO'
  native-path:          BAT0
  vendor:               SMP
  model:                01AV421
  power supply:         yes
  charge-cycles:        965
  energy-full:          13.6 Wh
  energy-full-design:   24.0 Wh
  capacity:             57%
INFO
add_device battery_BAT1 <<'INFO'
  native-path:          BAT1
  vendor:               LGC
  model:                01AV490
  power supply:         yes
  charge-cycles:        156
  energy-full:          10.1 Wh
  energy-full-design:   23.9 Wh
  capacity:             42%
INFO
add_device battery_hid_mouse <<'INFO'
  native-path:          /sys/devices/virtual/misc/uhid/0005:046D:B01D.0003
  model:                MX Master 3
  power supply:         no
  percentage:           70%
INFO

output=$(run_details)

grep -Fx $'BAT0\tlabel\tInternal' <<<"$output" >/dev/null || fail "power bridge names the built-in cell"
grep -Fx $'BAT1\tlabel\tExternal' <<<"$output" >/dev/null || fail "power bridge names the hot-swappable cell"
grep -Fx $'BAT0\tcycles\t965' <<<"$output" >/dev/null || fail "each cell keeps its own charge cycles"
grep -Fx $'BAT1\tcycles\t156' <<<"$output" >/dev/null || fail "each cell keeps its own charge cycles"
grep -Fx $'BAT0\thealth\t57%' <<<"$output" >/dev/null || fail "each cell keeps its own health"
grep -Fx $'BAT1\tsize\t10.1Wh' <<<"$output" >/dev/null || fail "each cell keeps its own capacity"
grep -q 'MX Master' <<<"$output" && fail "a peripheral is not a battery of this machine"
pass "power bridge cells are named and peripherals are left out"

# Anything that is not a two-cell ThinkPad gets ordinals rather than a guess,
# and the peripheral must not consume one of them.
new_machine ordinals "Precision 7550"
add_device battery_BAT0 <<'INFO'
  native-path:          BAT0
  power supply:         yes
  capacity:             90%
INFO
add_device battery_BAT1 <<'INFO'
  native-path:          BAT1
  power supply:         yes
  capacity:             88%
INFO
add_device battery_BAT2 <<'INFO'
  native-path:          BAT2
  power supply:         yes
  capacity:             81%
INFO

output=$(run_details)

grep -Fx $'BAT0\tlabel\tBattery 1' <<<"$output" >/dev/null || fail "unknown layouts fall back to ordinals"
grep -Fx $'BAT2\tlabel\tBattery 3' <<<"$output" >/dev/null || fail "ordinals cover any battery count"
pass "unknown layouts fall back to ordinals"

# One battery is just "Battery" — a paired mouse must not make it "Battery 1".
new_machine single "XPS 13"
add_device battery_BAT0 <<'INFO'
  native-path:          BAT0
  power supply:         yes
  capacity:             94%
INFO
add_device battery_hid_keyboard <<'INFO'
  native-path:          /sys/devices/virtual/misc/uhid/0005:05AC:0267.0004
  power supply:         no
  percentage:           55%
INFO

output=$(run_details)

grep -Fx $'BAT0\tlabel\tBattery' <<<"$output" >/dev/null || fail "a lone battery is not numbered"
pass "a lone battery is not numbered"

# A desktop with a wireless mouse has no battery to report.
new_machine desktop "OptiPlex 7090"
add_device battery_hid_mouse <<'INFO'
  native-path:          /sys/devices/virtual/misc/uhid/0005:046D:B01D.0003
  power supply:         no
  percentage:           70%
INFO

output=$(run_details)

[[ -z $output ]] || fail "a machine with no battery reports nothing"
pass "a machine with no battery reports nothing"
