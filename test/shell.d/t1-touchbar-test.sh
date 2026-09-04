#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-t1-touchbar.sh"
migration="$ROOT/migrations/1788507050.sh"
all="$ROOT/install/hardware/all.sh"
spi_leaf="$ROOT/install/hardware/apple/fix-spi-keyboard.sh"
manual="$ROOT/manual/44-mac-support.md"

grep -q 'apple/fix-t1-touchbar.sh' "$all" ||
  fail "T1 Touch Bar setup runs during hardware setup"
grep -q 'in_tree_applespi=' "$spi_leaf" ||
  fail "SPI setup detects the in-kernel driver before adding legacy DKMS"
grep -Fq 'forcing `skip_acpi_power=0` can hard-freeze' "$manual" ||
  fail "Mac support chapter documents the T1 freeze boundary"
pass "MacBookPro13,3 T1 support is wired and documented"

pkgs_candidates=(
  "$ROOT/../omarchy-pkgs/pkgbuilds"
  "$ROOT/../../omarchy-pkgs/pkgbuilds"
  "$HOME/Work/omacom/omarchy-pkgs/pkgbuilds"
)
if [[ -n ${OMARCHY_PKGS_PATH:-} ]]; then
  pkgs_candidates=("$OMARCHY_PKGS_PATH/pkgbuilds" "$OMARCHY_PKGS_PATH" "${pkgs_candidates[@]}")
fi

pkgbuild=""
for candidate in "${pkgs_candidates[@]}"; do
  if [[ -f $candidate/apple-ib-drv-dkms/PKGBUILD ]]; then
    pkgbuild="$candidate/apple-ib-drv-dkms/PKGBUILD"
    break
  fi
done
[[ -n $pkgbuild ]] || fail "apple-ib-drv-dkms package checkout is available"

grep -Fq 'v${pkgver}.tar.gz' "$pkgbuild" || fail "T1 package uses a tagged source archive"
grep -Fq "4092c93e450578c7de61e5c0452fae59ea7e49a7902464eb981c645f15988af5" "$pkgbuild" ||
  fail "T1 package pins the hardware-tested source archive hash"
grep -Fq "conflicts=('macbook12-spi-driver-dkms')" "$pkgbuild" ||
  fail "T1 package replaces the legacy conflicting DKMS source"
grep -Fq 'apple-touchbar.modprobe.conf' "$pkgbuild" ||
  fail "T1 package owns its freeze-safe module configuration"
grep -Fq 'ACTION=="add|change|bind"' "$(dirname "$pkgbuild")/99-ibridge.rules" ||
  fail "T1 package keeps iBridge autosuspend disabled after configuration changes"
pass "T1 driver and safety configuration are package-owned"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
dmi_product="$test_tmp/product_name"
usb_devices="$test_tmp/usb"
mkdir -p "$stub_bin" "$usb_devices/1-3"
: >"$calls"

cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'omarchy-pkg-add\t%s\n' "$*" >>"$TEST_LOG"
SH

cat >"$stub_bin/omarchy-pkg-missing" <<'SH'
#!/bin/bash
(( ${PACKAGE_MISSING:-1} == 1 ))
SH

cat >"$stub_bin/omarchy-state" <<'SH'
#!/bin/bash
printf 'omarchy-state\t%s\n' "$*" >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

invoke_leaf() {
  PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_INSTALL="$ROOT/install" \
    OMARCHY_T1_DMI_PRODUCT="$dmi_product" \
    OMARCHY_T1_USB_DEVICES="$usb_devices" \
    bash -euo pipefail -c 'source "$1"' bash "$leaf" >/dev/null
}

invoke_migration() {
  PACKAGE_MISSING="${1:-1}" PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_INSTALL="$ROOT/install" \
    OMARCHY_T1_DMI_PRODUCT="$dmi_product" \
    OMARCHY_T1_USB_DEVICES="$usb_devices" \
    bash -euo pipefail "$migration" >/dev/null
}

printf '05ac\n' >"$usb_devices/1-3/idVendor"
printf '8600\n' >"$usb_devices/1-3/idProduct"
printf 'MacBookPro13,3\n' >"$dmi_product"
invoke_leaf
grep -Fqx $'omarchy-pkg-add\tapple-ib-drv-dkms' "$calls" ||
  fail "MacBookPro13,3 with production iBridge gets the T1 package"
pass "MacBookPro13,3 with production iBridge gets Touch Bar support"

: >"$calls"
printf 'MacBookPro14,3\n' >"$dmi_product"
invoke_leaf
[[ ! -s $calls ]] || fail "unvalidated T1 models are left unchanged"
pass "automatic T1 support remains limited to the validated model"

: >"$calls"
printf 'MacBookPro13,3\n' >"$dmi_product"
printf '1281\n' >"$usb_devices/1-3/idProduct"
invoke_leaf
[[ ! -s $calls ]] || fail "recovery-mode iBridge is left unchanged"
pass "recovery-mode iBridge does not receive the Touch Bar driver"

printf '8600\n' >"$usb_devices/1-3/idProduct"
: >"$calls"
invoke_migration 1
grep -Fqx $'omarchy-pkg-add\tapple-ib-drv-dkms' "$calls" ||
  fail "migration installs the T1 package"
grep -Fqx $'omarchy-state\tset reboot-required' "$calls" ||
  fail "migration asks for the reboot that binds the driver"
pass "existing MacBookPro13,3 installs receive T1 support"

: >"$calls"
invoke_migration 0
[[ ! -s $calls ]] || fail "migration is quiet when the T1 package is installed"
pass "T1 migration is idempotent"
