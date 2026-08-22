#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

audio_installer="$ROOT/install/hardware/apple/install-macbookpro13-1-audio.sh"
camera_installer="$ROOT/install/hardware/apple/install-macbookpro13-1-camera.sh"
hardware_all="$ROOT/install/hardware/all.sh"
spi_installer="$ROOT/install/hardware/apple/fix-spi-keyboard.sh"
offline_packages="$ROOT/install/omarchy-other.packages"
migration="$ROOT/migrations/1787257711.sh"
mac_support_manual="$ROOT/manual/44-mac-support.md"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"
: >"$calls"

cat >"$stub_bin/omarchy-hw-match" <<'SH'
#!/bin/bash

(( ${MATCHING_HARDWARE:-0} == 1 ))
SH

cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash

printf 'omarchy-pkg-add' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

cat >"$stub_bin/omarchy-pkg-drop" <<'SH'
#!/bin/bash

printf 'omarchy-pkg-drop' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
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

run_capability_installer() {
  local installer="$1" matching_hardware="$2"
  : >"$calls"
  PATH="$stub_bin:$PATH" TEST_LOG="$calls" MATCHING_HARDWARE="$matching_hardware" \
    bash -eE -o pipefail -c 'source "$1"' bash "$installer" >/dev/null
}

run_migration() {
  local matching_hardware="$1"
  : >"$calls"
  PATH="$stub_bin:$PATH" TEST_LOG="$calls" MATCHING_HARDWARE="$matching_hardware" \
    OMARCHY_MACBOOKPRO13_1_MIGRATION_MARKER="$compatibility_marker" \
    bash -euo pipefail "$migration" >/dev/null
}

run_capability_installer "$audio_installer" 1

grep -Fxq $'omarchy-pkg-add\tsnd-hda-macbookpro-dkms' "$calls" ||
  fail "MacBookPro13,1 audio setup installs the Cirrus DKMS package" "$(cat "$calls")"
pass "MacBookPro13,1 audio setup installs the Cirrus DKMS package"

run_capability_installer "$audio_installer" 0

[[ ! -s $calls ]] ||
  fail "audio setup leaves other models untouched" "$(cat "$calls")"
pass "audio setup leaves other models untouched"

run_capability_installer "$camera_installer" 1

grep -Fxq $'omarchy-pkg-add\tfacetimehd-dkms\tfacetimehd-firmware' "$calls" ||
  fail "MacBookPro13,1 camera setup installs the driver and firmware packages" "$(cat "$calls")"
pass "MacBookPro13,1 camera setup installs the driver and firmware packages"

run_capability_installer "$camera_installer" 0

[[ ! -s $calls ]] ||
  fail "camera setup leaves other models untouched" "$(cat "$calls")"
pass "camera setup leaves other models untouched"

grep -Fq 'apple/install-macbookpro13-1-audio.sh' "$hardware_all" &&
  grep -Fq 'apple/install-macbookpro13-1-camera.sh' "$hardware_all" ||
  fail "hardware setup replays both MacBookPro13,1 capabilities"
pass "hardware setup replays both MacBookPro13,1 capabilities"

product_name="$test_tmp/product_name"
spi_conf_dir="$test_tmp/mkinitcpio.conf.d"
spi_test_script="$test_tmp/fix-spi-keyboard.sh"
sed -e "s|/sys/class/dmi/id/product_name|$product_name|g" \
    -e "s|/etc/mkinitcpio.conf.d|$spi_conf_dir|g" \
    "$spi_installer" >"$spi_test_script"

printf '%s\n' 'MacBookPro13,1' >"$product_name"
: >"$calls"
PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
  bash -eE -o pipefail -c 'source "$1"' bash "$spi_test_script" >/dev/null

! grep -Fq $'omarchy-pkg-add\tmacbook12-spi-driver-dkms' "$calls" ||
  fail "MacBookPro13,1 SPI setup uses the in-tree driver" "$(cat "$calls")"
pass "MacBookPro13,1 SPI setup uses the in-tree driver"

grep -Fxq 'MODULES=(applespi intel_lpss_pci spi_pxa2xx_platform)' \
  "$spi_conf_dir/macbook_spi_modules.conf" ||
  fail "MacBookPro13,1 SPI setup keeps the applespi initramfs configuration"
pass "MacBookPro13,1 SPI setup keeps the applespi initramfs configuration"

rm -rf "$spi_conf_dir"
printf '%s\n' 'MacBookPro13,2' >"$product_name"
: >"$calls"
PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
  bash -eE -o pipefail -c 'source "$1"' bash "$spi_test_script" >/dev/null

grep -Fq $'omarchy-pkg-add\tmacbook12-spi-driver-dkms' "$calls" ||
  fail "other supported MacBooks keep the SPI DKMS package" "$(cat "$calls")"
pass "other supported MacBooks keep the SPI DKMS package"

for package in facetimehd-dkms facetimehd-firmware snd-hda-macbookpro-dkms; do
  grep -Fxq "$package" "$offline_packages" ||
    fail "the offline package set includes MacBookPro13,1 compatibility packages" "$package is missing"
done
pass "the offline package set includes MacBookPro13,1 compatibility packages"

compatibility_marker="$test_tmp/macbookpro13-1-compatibility"
run_migration 1

grep -Fxq $'omarchy-pkg-add\tsnd-hda-macbookpro-dkms\tfacetimehd-dkms\tfacetimehd-firmware' "$calls" ||
  fail "the compatibility migration installs MacBookPro13,1 audio and camera support" "$(cat "$calls")"
pass "the compatibility migration installs MacBookPro13,1 audio and camera support"

grep -Fxq $'omarchy-pkg-drop\tmacbook12-spi-driver-dkms' "$calls" ||
  fail "the compatibility migration removes the obsolete SPI DKMS package" "$(cat "$calls")"
pass "the compatibility migration removes the obsolete SPI DKMS package"

grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "the compatibility migration regenerates the boot image" "$(cat "$calls")"
pass "the compatibility migration regenerates the boot image"

grep -Fxq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "the compatibility migration requests reboot" "$(cat "$calls")"
pass "the compatibility migration requests reboot"

[[ -f $compatibility_marker ]] ||
  fail "the compatibility migration records machine-level completion"
pass "the compatibility migration records machine-level completion"

run_migration 1

[[ ! -s $calls ]] ||
  fail "the compatibility migration is machine-idempotent" "$(cat "$calls")"
pass "the compatibility migration is machine-idempotent"

rm -f "$compatibility_marker"
run_migration 0

[[ ! -s $calls && ! -e $compatibility_marker ]] ||
  fail "the compatibility migration leaves other models untouched" "$(cat "$calls")"
pass "the compatibility migration leaves other models untouched"

grep -Fq '`MacBookPro13,1`' "$mac_support_manual" &&
  grep -Eqi 'deep suspend.*not supported|not supported.*deep suspend' "$mac_support_manual" &&
  grep -Eqi 'hibernation.*not supported|not supported.*hibernation' "$mac_support_manual" &&
  grep -Eqi 'audio.*camera.*do not always recover' "$mac_support_manual" &&
  grep -Eqi 'shutdown.*reboot|reboot.*shutdown' "$mac_support_manual" &&
  ! grep -Eqi 'first[- ]iteration' "$mac_support_manual" ||
  fail "the Mac manual documents the exact support contract and upstream limitations"
pass "the Mac manual documents the exact support contract and upstream limitations"
