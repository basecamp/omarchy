#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

bind="$ROOT/bin/omarchy-hw-apple-t1-touchbar-disp-bind"
helpers="$ROOT/install/hardware/apple/t1-touchbar-disp-bind.sh"
fix="$ROOT/install/hardware/apple/fix-t1-touchbar-disp-bind.sh"
rule="$ROOT/default/udev/apple-t1-touchbar-disp.rules"
migration="$ROOT/migrations/1787508990.sh"

[[ -x $bind ]] || fail "the rebind script is executable"

grep -Fq 'omarchy-hw-apple-t1-touchbar-disp-bind' "$rule" ||
  fail "udev rule runs the rebind script"
grep -Fq 'idProduct}=="8600"' "$rule" ||
  fail "udev rule fires on the iBridge USB device, not just module load"
pass "udev rule rebinds on every iBridge (re)enumeration, including resume"

grep -Fq 'fix-t1-touchbar-disp-bind.sh' "$ROOT/install/hardware/all.sh" ||
  fail "hardware install runs the display-bind hook"
pass "display-bind hook is wired into the installer"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

# --- hardware gate ---
# shellcheck source=../../install/hardware/apple/t1-touchbar-disp-bind.sh
source "$helpers"

assert_needed() {
  local model=$1 expect=$2 description=$3
  local tmp
  tmp=$(mktemp)
  printf '%s\n' "$model" >"$tmp"
  if OMARCHY_DMI_PRODUCT_NAME="$tmp" t1_touchbar_disp_needed; then
    [[ $expect == yes ]] || fail "$description"
  else
    [[ $expect == no ]] || fail "$description"
  fi
  rm -f "$tmp"
  pass "$description"
}

assert_needed MacBookPro14,3 yes "MacBookPro14,3 is a T1 Touch Bar"
assert_needed MacBookPro13,2 yes "MacBookPro13,2 is a T1 Touch Bar"
assert_needed MacBookPro14,2 yes "MacBookPro14,2 is a T1 Touch Bar"
assert_needed MacBookPro13,1 no "MacBookPro13,1 has no Touch Bar"
assert_needed MacBookPro15,1 no "MacBookPro15,1 is T2, not T1"

# --- rebind script against a faked /sys/bus/hid tree ---
# The real unbind/bind sysfs files are write-only actions the kernel consumes
# to move a driver symlink; a plain tmp file can't reproduce that, so these
# assert on which files the script writes to rather than the resulting link.
hid_root="$test_tmp/hid"
mkdir -p "$hid_root/devices" "$hid_root/drivers/hid-sensor-hub" "$hid_root/drivers/apple-ib-touchbar"
: >"$hid_root/drivers/hid-sensor-hub/unbind"
: >"$hid_root/drivers/apple-ib-touchbar/bind"

dev="$hid_root/devices/0003:1D6B:0301.0042"
mkdir -p "$dev"
ln -s "../../drivers/hid-sensor-hub" "$dev/driver"

OMARCHY_T1_HID_ROOT="$hid_root" "$bind"
[[ -s $hid_root/drivers/hid-sensor-hub/unbind ]] ||
  fail "rebind script unbinds the sub-device from whatever driver holds it"
[[ -s $hid_root/drivers/apple-ib-touchbar/bind ]] ||
  fail "rebind script binds the sub-device to apple-ib-touchbar"
pass "rebind script moves the virtual sub-device onto apple-ib-touchbar"

# Already on the right driver: no unbind attempted.
already_root="$test_tmp/hid-already"
mkdir -p "$already_root/devices" "$already_root/drivers/apple-ib-touchbar"
already_dev="$already_root/devices/0003:1D6B:0301.0042"
mkdir -p "$already_dev"
ln -s "../../drivers/apple-ib-touchbar" "$already_dev/driver"
OMARCHY_T1_HID_ROOT="$already_root" "$bind"
[[ -L $already_dev/driver ]] || fail "already-bound sub-device keeps its driver link"
pass "rebind script is a no-op once the sub-device is already on apple-ib-touchbar"

# No sub-device present yet: give up after the retry budget instead of hanging.
empty_root="$test_tmp/hid-empty"
mkdir -p "$empty_root/devices"
time_start=$SECONDS
OMARCHY_T1_HID_ROOT="$empty_root" "$bind"
(( SECONDS - time_start < 10 )) ||
  fail "rebind script does not hang when the sub-device never appears"
pass "rebind script gives up after its retry budget with no sub-device present"

# --- install hook + migration wiring ---
stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH
cat >"$stub_bin/udevadm" <<'SH'
#!/bin/bash
printf 'udevadm' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH
chmod +x "$stub_bin"/*

dmi="$test_tmp/dmi"
rule_dest="$test_tmp/etc/udev/rules.d/91-apple-t1-touchbar-disp.rules"

printf 'MacBookPro14,1\n' >"$dmi"
: >"$calls"
PATH="$stub_bin:$PATH" \
  TEST_LOG="$calls" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_INSTALL="$ROOT/install" \
  OMARCHY_DMI_PRODUCT_NAME="$dmi" \
  OMARCHY_T1_DISP_RULE_DEST="$rule_dest" \
  bash -c 'source "$1"' _ "$fix"
[[ ! -f $rule_dest ]] || fail "install hook no-ops on non-T1 hardware"
pass "install hook no-ops on non-T1 hardware"

printf 'MacBookPro14,2\n' >"$dmi"
: >"$calls"
PATH="$stub_bin:$PATH" \
  TEST_LOG="$calls" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_INSTALL="$ROOT/install" \
  OMARCHY_DMI_PRODUCT_NAME="$dmi" \
  OMARCHY_T1_DISP_RULE_DEST="$rule_dest" \
  bash -c 'source "$1"' _ "$fix"
[[ -f $rule_dest ]] || fail "install hook writes the udev rule on T1 hardware"
grep -Fq $'udevadm\tcontrol\t--reload' "$calls" ||
  fail "install hook reloads udev after writing the rule"
pass "install hook wires the display-bind fix on T1 hardware"

rm -f "$rule_dest"
: >"$calls"
PATH="$stub_bin:$PATH" \
  TEST_LOG="$calls" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_INSTALL="$ROOT/install" \
  OMARCHY_DMI_PRODUCT_NAME="$dmi" \
  OMARCHY_T1_DISP_RULE_DEST="$rule_dest" \
  bash -euo pipefail "$migration"
[[ -f $rule_dest ]] || fail "migration writes the udev rule on existing T1 installs"
pass "migration wires the display-bind fix on existing T1 installs"

: >"$calls"
PATH="$stub_bin:$PATH" \
  TEST_LOG="$calls" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_INSTALL="$ROOT/install" \
  OMARCHY_DMI_PRODUCT_NAME="$dmi" \
  OMARCHY_T1_DISP_RULE_DEST="$rule_dest" \
  bash -euo pipefail "$migration"
[[ ! -s $calls ]] || fail "migration is idempotent once already wired" "$(cat "$calls")"
pass "migration is a no-op on a machine already wired up"

printf 'MacBookPro16,1\n' >"$dmi"
rm -f "$rule_dest"
: >"$calls"
PATH="$stub_bin:$PATH" \
  TEST_LOG="$calls" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_INSTALL="$ROOT/install" \
  OMARCHY_DMI_PRODUCT_NAME="$dmi" \
  OMARCHY_T1_DISP_RULE_DEST="$rule_dest" \
  bash -euo pipefail "$migration"
[[ ! -f $rule_dest ]] || fail "migration skips unrelated hardware"
[[ ! -s $calls ]] || fail "migration skips unrelated hardware" "$(cat "$calls")"
pass "migration skips unrelated hardware"
