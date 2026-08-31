#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-magic-trackpad.sh"
all="$ROOT/install/hardware/all.sh"
migration="$ROOT/migrations/1788129995.sh"
input_lua="$ROOT/default/hypr/input.lua"

grep -q 'apple/fix-magic-trackpad.sh' "$all" ||
  fail "the Magic Trackpad quirk runs during hardware setup"
pass "the Magic Trackpad quirk runs during hardware setup"

grep -q 'apple-inc.-magic-trackpad' "$input_lua" ||
  fail "Hyprland defaults pin Magic Trackpad sensitivity"
grep -q 'accel_profile = "adaptive"' "$input_lua" ||
  fail "Hyprland defaults keep adaptive accel on the Magic Trackpad"
pass "Hyprland defaults pin Magic Trackpad pointer feel"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
hid_dir="$test_tmp/hid"
quirks="$test_tmp/etc/libinput/omarchy-magic-trackpad.quirks"
modprobe_conf="$test_tmp/etc/modprobe.d/omarchy-magic-trackpad.conf"
sysfs="$test_tmp/sys/hid_magicmouse"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

chmod +x "$stub_bin"/*

add_hid() {
  local id=$1
  local dir="$hid_dir/$id"
  mkdir -p "$dir"
  printf 'HID_ID=%s\nHID_NAME=fixture\n' "$id" >"$dir/uevent"
}

run_leaf() {
  rm -rf "$test_tmp/etc" "$hid_dir"
  mkdir -p "$test_tmp/etc" "$hid_dir"
  for id in "$@"; do
    add_hid "$id"
  done

  TEST_LOG="$calls" PATH="$stub_bin:$ROOT/bin:$PATH" \
    OMARCHY_HID_DEVICES_DIR="$hid_dir" \
    OMARCHY_MAGIC_TRACKPAD_QUIRKS="$quirks" \
    OMARCHY_HID_MAGICMOUSE_CONF="$modprobe_conf" \
    bash -eE -o pipefail -c 'source "$1"' bash "$leaf"
}

run_leaf "0003:000005AC:00000265"
[[ -f $quirks ]] || fail "a Magic Trackpad install writes libinput quirks"
grep -q 'AttrTouchSizeRange=40:20' "$quirks" ||
  fail "libinput quirks re-enable size-based thumb filtering"
grep -q 'emulate_scroll_wheel=0' "$modprobe_conf" ||
  fail "a Magic Trackpad install disables hid-magicmouse scroll emulation"
grep -q 'emulate_3button=0' "$modprobe_conf" ||
  fail "a Magic Trackpad install disables hid-magicmouse 3-button emulation"
pass "a Magic Trackpad install writes quirks and kernel options"

run_leaf
[[ -f $quirks ]] || fail "libinput quirks are installed even without the pad present"
[[ ! -f $modprobe_conf ]] || fail "kernel options wait until a Magic Trackpad is present"
pass "kernel options are skipped when no Magic Trackpad is connected"

run_leaf "0003:000005AC:00000265" "0005:0000004C:00000269"
[[ -f $quirks ]] || fail "quirks still install next to a Magic Mouse"
[[ ! -f $modprobe_conf ]] ||
  fail "kernel options are skipped when a Magic Mouse is present" "$(cat "$modprobe_conf")"
pass "a Magic Mouse keeps kernel surface-scroll emulation"

run_leaf "0005:0000004C:00000324"
grep -q 'emulate_scroll_wheel=0' "$modprobe_conf" ||
  fail "a Bluetooth USB-C Magic Trackpad is recognized"
pass "Bluetooth USB-C Magic Trackpad IDs are recognized"

run_migration() {
  rm -rf "$test_tmp/etc" "$hid_dir"
  mkdir -p "$test_tmp/etc" "$hid_dir"
  : >"$calls"
  for id in "$@"; do
    add_hid "$id"
  done

  TEST_LOG="$calls" PATH="$stub_bin:$ROOT/bin:$PATH" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_HID_DEVICES_DIR="$hid_dir" \
    OMARCHY_MAGIC_TRACKPAD_QUIRKS="$quirks" \
    OMARCHY_HID_MAGICMOUSE_CONF="$modprobe_conf" \
    OMARCHY_HID_MAGICMOUSE_SYSFS="$sysfs" \
    bash -euo pipefail "$migration" >/dev/null
}

rm -rf "$sysfs"
run_migration "0003:000005AC:00000265"
[[ -f $quirks ]] || fail "the migration writes libinput quirks"
grep -q 'emulate_scroll_wheel=0' "$modprobe_conf" ||
  fail "the migration writes hid-magicmouse options"
[[ ! -e $sysfs/emulate_scroll_wheel ]] ||
  fail "the migration does not invent sysfs nodes"
pass "the migration installs Magic Trackpad config without a loaded module"

mkdir -p "$sysfs"
printf 'Y\n' >"$sysfs/emulate_scroll_wheel"
printf 'Y\n' >"$sysfs/emulate_3button"
printf 'Y\n' >"$sysfs/scroll_acceleration"
run_migration "0003:000005AC:00000265"
[[ $(<"$sysfs/emulate_scroll_wheel") == N ]] ||
  fail "the migration applies kernel options to a loaded module" "$(cat "$sysfs/emulate_scroll_wheel")"
[[ $(<"$sysfs/emulate_3button") == N ]] ||
  fail "the migration turns off 3-button emulation live"
pass "the migration applies hid-magicmouse options without a reboot"

printf 'Y\n' >"$sysfs/emulate_scroll_wheel"
printf 'Y\n' >"$sysfs/emulate_3button"
printf 'Y\n' >"$sysfs/scroll_acceleration"
run_migration "0003:000005AC:0000030D"
[[ -f $quirks ]] || fail "the migration still writes quirks on a Magic Mouse machine"
[[ ! -f $modprobe_conf ]] || fail "the migration leaves Magic Mouse kernel options alone"
[[ $(<"$sysfs/emulate_scroll_wheel") == Y ]] ||
  fail "the migration does not rewrite Magic Mouse sysfs"
pass "the migration leaves Magic Mouse kernel emulation alone"
