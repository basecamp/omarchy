#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

devices_file="$test_tmp/devices"

has_i2c_keyboard() {
  OMARCHY_INPUT_DEVICES_PATH="$devices_file" "$ROOT/bin/omarchy-hw-i2c-hid-keyboard"
}

: >"$devices_file"
if has_i2c_keyboard; then
  fail "an empty device list has no I2C-HID keyboard"
fi
pass "I2C-HID keyboard detection handles an empty device list"

cat >"$devices_file" <<'EOF'
N: Name="AT Translated Set 2 keyboard"
P: Phys=isa0060/serio0/input0
H: Handlers=sysrq kbd leds event3 

EOF
if has_i2c_keyboard; then
  fail "a PS/2-only keyboard is not reported as I2C-HID"
fi
pass "I2C-HID keyboard detection ignores PS/2 keyboards"

cat >"$devices_file" <<'EOF'
N: Name="ASUE140C:00 04F3:3145 Touchpad"
P: Phys=i2c-ASUE140C:00
H: Handlers=event15 mouse2 

EOF
if has_i2c_keyboard; then
  fail "an I2C touchpad without a kbd handler is not reported as a keyboard"
fi
pass "I2C-HID keyboard detection ignores I2C touchpads"

cat >"$devices_file" <<'EOF'
N: Name="ASUE140C:00 04F3:3145 Touchpad"
P: Phys=i2c-ASUE140C:00
H: Handlers=event15 mouse2 

N: Name="AT Translated Set 2 keyboard"
P: Phys=isa0060/serio0/input0
H: Handlers=sysrq kbd leds event3 

EOF
if has_i2c_keyboard; then
  fail "a PS/2 keyboard after an I2C touchpad is not attributed to the I2C bus"
fi
pass "I2C-HID keyboard detection keeps device blocks separate"

cat >"$devices_file" <<'EOF'
N: Name="AT Translated Set 2 keyboard"
P: Phys=isa0060/serio0/input0
H: Handlers=sysrq kbd leds event3 

N: Name="ASUE140C:00 04F3:3145 Keyboard"
P: Phys=i2c-ASUE140C:00
H: Handlers=sysrq kbd leds event23 

EOF
has_i2c_keyboard || fail "an I2C-HID keyboard alongside a PS/2 stub is detected"
pass "I2C-HID keyboard detection finds a keyboard on the I2C bus"

cat >"$devices_file" <<'EOF'
N: Name="Power Button"
P: Phys=PNP0C0C/button/input0
H: Handlers=kbd event1 

EOF
if has_i2c_keyboard; then
  fail "a non-I2C kbd handler is not reported as an I2C-HID keyboard"
fi
pass "I2C-HID keyboard detection ignores kbd handlers off the I2C bus"
