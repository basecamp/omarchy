#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-sd-card-reader.sh"
hw="$ROOT/bin/omarchy-hw-apple-sd-reader"
cmd="$ROOT/bin/omarchy-cmd-apple-sd-reader"
all="$ROOT/install/hardware/all.sh"
manual="$ROOT/manual/44-mac-support.md"
migration="$ROOT/migrations/1788508170.sh"

grep -q 'apple/fix-sd-card-reader.sh' "$all" ||
  fail "the Apple SD reader fix runs during hardware setup"
grep -q 'usbcore.quirks=05ac:8406:bk' "$leaf" ||
  fail "the install leaf puts the Apple reader quirk on the kernel command line"
grep -q 'acpi_call' "$leaf" ||
  fail "the install leaf installs acpi_call for SPWR/SRST"
grep -q 'SPWR' "$cmd" ||
  fail "the helper calls Apple XHCI SPWR"
grep -q '05ac:8406' "$manual" ||
  fail "Mac support documents the SD reader keep-alive"
grep -q 'fix-sd-card-reader.sh' "$migration" ||
  fail "a migration applies the Apple SD reader fix on existing installs"
pass "the Apple SD reader fix is wired into hardware setup"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
dmi="$test_tmp/product_name"
mkdir -p "$stub_bin" "$test_tmp/limine" "$test_tmp/udev" "$test_tmp/sleep"
: >"$calls"

printf 'MacBookPro12,1\n' >"$dmi"

OMARCHY_DMI_PRODUCT_NAME=$dmi "$hw"
pass "detector matches MacBookPro12,1"

printf 'MacBookPro14,1\n' >"$dmi"
if OMARCHY_DMI_PRODUCT_NAME=$dmi "$hw"; then
  fail "detector ignores MacBookPro14,1"
fi
pass "detector skips Macs without the Apple USB reader"

printf 'MacBookAir7,2\n' >"$dmi"
OMARCHY_DMI_PRODUCT_NAME=$dmi "$hw"
pass "detector matches MacBookAir7,2"

cat >"$stub_bin/omarchy-hw-apple-sd-reader" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$stub_bin/omarchy-hw-apple-sd-reader-miss" <<'SH'
#!/bin/bash
exit 1
SH

cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'omarchy-pkg-add' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
[[ $1 == "limine-mkinitcpio" ]]
SH

cat >"$stub_bin/omarchy-state" <<'SH'
#!/bin/bash
printf 'omarchy-state' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

cat >"$stub_bin/limine-mkinitcpio" <<'SH'
#!/bin/bash
echo 'limine-mkinitcpio' >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

limine_conf="$test_tmp/limine/apple-sd-reader.conf"
udev_rules="$test_tmp/udev/90-omarchy-apple-sd-reader.rules"
sleep_hook="$test_tmp/sleep/omarchy-apple-sd-reader"

run_leaf() {
  PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_APPLE_SD_LIMINE_CONF="$limine_conf" \
    OMARCHY_APPLE_SD_UDEV_RULES="$udev_rules" \
    OMARCHY_APPLE_SD_SLEEP_HOOK="$sleep_hook" \
    bash -euo pipefail -c 'source "$1"' _ "$leaf"
}

: >"$calls"
run_leaf

grep -Fq 'KERNEL_CMDLINE[default]+=" usbcore.quirks=05ac:8406:bk usbcore.autosuspend=-1"' "$limine_conf" ||
  fail "leaf writes the Limine quirk drop-in"
grep -q 'idProduct}=="8406"' "$udev_rules" ||
  fail "leaf writes the udev keep-alive rule"
grep -q 'omarchy-cmd-apple-sd-reader' "$sleep_hook" ||
  fail "sleep hook calls the Apple SD reader helper"
[[ -x $sleep_hook ]] || fail "sleep hook is executable"
grep -Fxq $'omarchy-pkg-add\tacpi_call' "$calls" ||
  fail "leaf installs acpi_call"
grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "leaf rebuilds the boot image"
grep -Fxq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "leaf marks reboot required"
pass "leaf installs cmdline, udev, sleep hook, and acpi_call"

# Non-matching hardware: replace the detector on PATH with a miss.
mv "$stub_bin/omarchy-hw-apple-sd-reader" "$stub_bin/omarchy-hw-apple-sd-reader.hit"
cp "$stub_bin/omarchy-hw-apple-sd-reader-miss" "$stub_bin/omarchy-hw-apple-sd-reader"
: >"$calls"
rm -f "$limine_conf"
PATH="$stub_bin:$PATH" \
  TEST_LOG="$calls" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_APPLE_SD_LIMINE_CONF="$limine_conf" \
  OMARCHY_APPLE_SD_UDEV_RULES="$udev_rules" \
  OMARCHY_APPLE_SD_SLEEP_HOOK="$sleep_hook" \
  bash -euo pipefail -c 'source "$1"' _ "$leaf"
[[ ! -e $limine_conf ]] || fail "non-matching hardware does not write Limine config"
[[ ! -s $calls ]] || fail "non-matching hardware is a no-op" "$(cat "$calls")"
pass "leaf is a no-op on machines without the Apple USB reader"
