#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

hw="$ROOT/bin/omarchy-hw-apple-t1"
helpers="$ROOT/install/hardware/apple/t1-touchbar.sh"
fix="$ROOT/install/hardware/apple/fix-t1-touchbar.sh"
collector="$ROOT/install/hardware/apple/copy-t1-firmware.command"
udev_src="$ROOT/default/udev/apple-t1-touchbar.rules"
setup="$ROOT/bin/omarchy-setup-apple-touchbar"
migration="$ROOT/migrations/1786820569.sh"
menu="$ROOT/default/omarchy/omarchy-menu.jsonc"
manual="$ROOT/manual/44-mac-support.md"

assert_hw() {
  local model=$1 expect=$2 description=$3
  local tmp
  tmp=$(mktemp)
  printf '%s\n' "$model" >"$tmp"
  if OMARCHY_DMI_PRODUCT_NAME="$tmp" "$hw"; then
    [[ $expect == yes ]] || fail "$description"
  else
    [[ $expect == no ]] || fail "$description"
  fi
  rm -f "$tmp"
  pass "$description"
}

assert_hw MacBookPro14,3 yes "MacBookPro14,3 is a T1 Touch Bar"
assert_hw MacBookPro13,2 yes "MacBookPro13,2 is a T1 Touch Bar"
assert_hw MacBookPro13,3 yes "MacBookPro13,3 is a T1 Touch Bar"
assert_hw MacBookPro14,2 yes "MacBookPro14,2 is a T1 Touch Bar"
assert_hw MacBookPro13,1 no "MacBookPro13,1 has no Touch Bar"
assert_hw MacBookPro14,1 no "MacBookPro14,1 has no Touch Bar"
assert_hw MacBookPro15,1 no "MacBookPro15,1 is T2, not T1"
assert_hw MacBook8,1 no "MacBook8,1 is SPI-only"

[[ -f $collector ]] || fail "macOS collector is in the tree"
head -1 "$collector" | grep -qx '#!/bin/bash' || fail "macOS collector uses /bin/bash"
! grep -qE 'mapfile|declare -A|\[\[.*-v |&\>' "$collector" ||
  fail "macOS collector stays on bash 3.2"
grep -Fq 'omarchy setup apple touchbar' "$collector" ||
  fail "macOS collector points at the Linux setup command"
pass "macOS collector is Finder-runnable and bash 3.2 safe"

grep -Fq 'omarchy-hw-apple-t1-bind' "$udev_src" ||
  fail "udev rule runs the packaged bind command"
pass "udev rule rebinds when apple_ib_tb loads"

grep -Fq 'fix-t1-touchbar.sh' "$ROOT/install/hardware/all.sh" ||
  fail "hardware install runs the T1 hook after the SPI keyboard hook"
pass "T1 install hook is wired"

grep -Fq 'omarchy-setup-apple-touchbar' "$menu" ||
  fail "Setup menu offers Touch Bar firmware on T1 hardware"
grep -Fq 'omarchy-hw-apple-t1' "$menu" ||
  fail "Touch Bar menu row is gated on T1 detection"
pass "Setup menu exposes the firmware wizard on T1 machines"

grep -Fq 'omarchy setup apple touchbar' "$manual" ||
  fail "Mac support chapter documents the setup command"
! grep -q 'Touch Bar is non-functional' "$manual" ||
  fail "Mac support chapter no longer lists the bar as unsupported"
grep -Fq 'install/hardware/apple/copy-t1-firmware.command' "$manual" ||
  fail "Mac support chapter names the ISO collector path"
! grep -q '/raw/quattro/' "$manual" ||
  fail "Mac support chapter does not pin the collector to the quattro branch"
grep -Fq 'https://github.com/basecamp/omarchy/raw/HEAD/install/hardware/apple/copy-t1-firmware.command' "$manual" ||
  fail "Mac support chapter uses a durable GitHub HEAD URL"
pass "Mac support chapter documents the USB handoff"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

# shellcheck source=../../install/hardware/apple/t1-touchbar.sh
OMARCHY_PATH="$ROOT" source "$helpers"

usb="$test_tmp/usb"
esp="$test_tmp/esp"
etc="$test_tmp/etc"
mkdir -p "$usb/APPLE/EMBEDDEDOS" "$esp" "$etc/udev/rules.d" "$etc/modules-load.d"
printf 'memboot\n' >"$usb/APPLE/EMBEDDEDOS/combined.memboot"
printf 'fdr\n' >"$usb/APPLE/EMBEDDEDOS/FDRData"
printf 'plist\n' >"$usb/APPLE/EMBEDDEDOS/version.plist"

OMARCHY_PATH="$ROOT"
OMARCHY_T1_MEDIA_ROOTS="$usb"
OMARCHY_T1_ESP="$esp"
OMARCHY_T1_UDEV_SRC="$udev_src"
OMARCHY_T1_UDEV_DEST="$etc/udev/rules.d/90-apple-t1-touchbar.rules"
OMARCHY_T1_MODULES_LOAD="$etc/modules-load.d/apple-t1-touchbar.conf"
OMARCHY_T1_COLLECTOR="$collector"

src=$(t1_find_firmware) || fail "firmware is found on a mounted USB"
[[ $src == "$usb/APPLE" ]] || fail "firmware path is the APPLE tree"
pass "firmware lookup finds APPLE/EMBEDDEDOS on USB"

t1_copy_firmware "$src" "$esp" || fail "firmware copy succeeds"
[[ -s $esp/EFI/APPLE/EMBEDDEDOS/combined.memboot ]] || fail "combined.memboot landed on the ESP"
[[ $(cat "$esp/EFI/APPLE/EMBEDDEDOS/FDRData") == fdr ]] || fail "FDRData is copied with the tree"
t1_firmware_present || fail "firmware presence check sees the ESP copy"
pass "firmware copy lands on the ESP without preserving Unix ownership"

empty_usb="$test_tmp/empty"
mkdir -p "$empty_usb"
OMARCHY_T1_MEDIA_ROOTS="$empty_usb"
t1_write_collector "$empty_usb"
[[ -x $empty_usb/copy-t1-firmware.command ]] || fail "collector is executable on the USB"
grep -Fq 'diskutil' "$empty_usb/copy-t1-firmware.command" ||
  fail "collector written to USB is the macOS script"
pass "a firmware-less USB receives the macOS collector"

t1_install_wiring
grep -Fq 'omarchy-hw-apple-t1-bind' "$OMARCHY_T1_UDEV_DEST" ||
  fail "wiring installs the udev rule"
grep -Fxq 'apple-ib-tb' "$OMARCHY_T1_MODULES_LOAD" ||
  fail "wiring loads apple-ib-tb"
pass "wiring installs the udev rule and module list"

dmi="$test_tmp/dmi"
printf 'MacBookPro14,1\n' >"$dmi"
PATH="$ROOT/bin:$PATH" \
  OMARCHY_DMI_PRODUCT_NAME="$dmi" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_INSTALL="$ROOT/install" \
  bash -c 'source "$1"' _ "$fix"
pass "install hook no-ops on non-T1 hardware"

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"
cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'omarchy-pkg-add' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH
cat >"$stub_bin/omarchy-hw-apple-t1" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$stub_bin"/*

printf 'MacBookPro14,3\n' >"$dmi"
install_etc="$test_tmp/install-etc"
mkdir -p "$install_etc/udev/rules.d" "$install_etc/modules-load.d"
calls="$test_tmp/calls.log"
: >"$calls"
PATH="$stub_bin:$ROOT/bin:$PATH" \
  TEST_LOG="$calls" \
  OMARCHY_DMI_PRODUCT_NAME="$dmi" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_INSTALL="$ROOT/install" \
  OMARCHY_T1_UDEV_SRC="$udev_src" \
  OMARCHY_T1_UDEV_DEST="$install_etc/udev/rules.d/90-apple-t1-touchbar.rules" \
  OMARCHY_T1_MODULES_LOAD="$install_etc/modules-load.d/apple-t1-touchbar.conf" \
  OMARCHY_T1_ESP="$esp" \
  OMARCHY_T1_MEDIA_ROOTS="$usb" \
  bash -c 'source "$1"' _ "$fix"
grep -Fq $'omarchy-pkg-add\tlinux-headers' "$calls" ||
  fail "T1 install hook installs linux-headers"
[[ -f $install_etc/udev/rules.d/90-apple-t1-touchbar.rules ]] ||
  fail "T1 install hook writes udev wiring"
[[ -s $esp/EFI/APPLE/EMBEDDEDOS/combined.memboot ]] ||
  fail "T1 install hook copies firmware when the USB is mounted"
pass "install hook copies firmware and wiring on T1 hardware"

calls="$test_tmp/calls.log"
: >"$calls"
PATH="$stub_bin:$PATH" \
  TEST_LOG="$calls" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_DMI_PRODUCT_NAME="$dmi" \
  OMARCHY_T1_UDEV_SRC="$udev_src" \
  OMARCHY_T1_UDEV_DEST="$etc/udev/rules.d/90-apple-t1-touchbar.rules" \
  OMARCHY_T1_MODULES_LOAD="$etc/modules-load.d/apple-t1-touchbar.conf" \
  OMARCHY_T1_ESP="$esp" \
  OMARCHY_T1_MEDIA_ROOTS="$empty_usb" \
  bash -euo pipefail "$migration"

grep -Fq $'omarchy-pkg-add\tlinux-headers' "$calls" ||
  fail "T1 migration installs linux-headers"
[[ -f $OMARCHY_T1_UDEV_DEST ]] || fail "T1 migration writes the udev rule"
pass "T1 migration installs wiring on T1 hardware"

fail_esp="$test_tmp/fail-esp"
printf 'not-a-dir\n' >"$fail_esp"
copy_log="$test_tmp/copy-fail.log"
: >"$calls"
PATH="$stub_bin:$PATH" \
  TEST_LOG="$calls" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_DMI_PRODUCT_NAME="$dmi" \
  OMARCHY_T1_UDEV_SRC="$udev_src" \
  OMARCHY_T1_UDEV_DEST="$etc/udev/rules.d/90-apple-t1-touchbar.rules" \
  OMARCHY_T1_MODULES_LOAD="$etc/modules-load.d/apple-t1-touchbar.conf" \
  OMARCHY_T1_ESP="$fail_esp" \
  OMARCHY_T1_MEDIA_ROOTS="$usb" \
  bash -euo pipefail "$migration" >"$copy_log" 2>&1
[[ -f $OMARCHY_T1_UDEV_DEST ]] || fail "T1 migration keeps wiring after a firmware copy failure"
grep -Fq 'could not copy it to the EFI partition' "$copy_log" ||
  fail "T1 migration reports a firmware copy failure" "$(cat "$copy_log")"
grep -Fq 'omarchy setup apple touchbar' "$copy_log" ||
  fail "T1 migration points at the setup command after a copy failure" "$(cat "$copy_log")"
pass "T1 migration reports a firmware copy failure without aborting"

cat >"$stub_bin/omarchy-hw-apple-t1" <<'SH'
#!/bin/bash
exit 1
SH
: >"$calls"
PATH="$stub_bin:$PATH" \
  TEST_LOG="$calls" \
  OMARCHY_PATH="$ROOT" \
  bash -euo pipefail "$migration"
[[ ! -s $calls ]] || fail "non-T1 migration is a no-op" "$(cat "$calls")"
pass "T1 migration skips unrelated hardware"
