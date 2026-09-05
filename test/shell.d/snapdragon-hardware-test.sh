#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

firmware_setup="$ROOT/install/hardware/qualcomm/firmware.sh"
dtb_setup="$ROOT/install/hardware/qualcomm/dtb-uki.sh"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

bash -n "$firmware_setup" "$dtb_setup" || fail "Snapdragon hardware scripts have valid syntax"

(
  omarchy-hw-qualcomm-soc() { return 0; }
  omarchy-pkg-add() { :; }
  qcom-firmware-extract() { :; }
  findmnt() {
    [[ $* == "-no SOURCE --nofsroot /" ]] || fail "Snapdragon firmware setup strips the Btrfs subvolume suffix"
    printf '/dev/mapper/root\n'
  }
  lsblk() {
    [[ ${!#} == "/dev/mapper/root" ]] || fail "Snapdragon firmware setup passes a resolvable root device to lsblk"
    printf 'usb\n'
  }

  OMARCHY_QUALCOMM_MODPROBE_DIR="$scratch/modprobe.d"
  source "$firmware_setup"
)

[[ -f $scratch/modprobe.d/qualcomm-adsp-nofw.conf ]] ||
  fail "Snapdragon firmware setup protects a USB-backed root disk"

mkdir -p "$scratch/dtbs"
: >"$scratch/dtbs/x1e80100-test.dtb"
: >"$scratch/dtbs/x1e80100-test-el2.dtb"
cat >"$scratch/uki.conf" <<'CONF'
[UKI]
SecureBootPrivateKey=/secure/db.key
PCRPrivateKey=/secure/pcr.key
CONF

run_dtb_setup() (
  omarchy-hw-qualcomm-soc() { return 0; }
  omarchy-pkg-add() { :; }

  OMARCHY_QUALCOMM_DTB_DIR="$scratch/dtbs"
  OMARCHY_QUALCOMM_UKI_CONFIG="$scratch/uki.conf"
  source "$dtb_setup"
)

run_dtb_setup
run_dtb_setup

grep -Fq 'SecureBootPrivateKey=/secure/db.key' "$scratch/uki.conf" ||
  fail "Snapdragon DTB setup preserves Secure Boot settings"
grep -Fq 'PCRPrivateKey=/secure/pcr.key' "$scratch/uki.conf" ||
  fail "Snapdragon DTB setup preserves PCR settings"
[[ $(grep -Fc '# BEGIN OMARCHY QUALCOMM DEVICE TREES' "$scratch/uki.conf") == 1 ]] ||
  fail "Snapdragon DTB setup keeps one managed UKI block"
grep -Fq "DeviceTreeAuto=$scratch/dtbs/x1e80100-test.dtb" "$scratch/uki.conf" ||
  fail "Snapdragon DTB setup lists the matching device tree"
if grep -Fq 'x1e80100-test-el2.dtb' "$scratch/uki.conf"; then
  fail "Snapdragon DTB setup excludes EL2-only device trees"
fi

pass "Snapdragon setup preserves UKI settings and detects USB root disks"
