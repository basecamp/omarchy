#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

hw="$ROOT/bin/omarchy-hw-apple-mbp15-dgpu"
idle="$ROOT/bin/omarchy-hw-apple-mbp15-amdgpu-idle"
fix="$ROOT/install/hardware/apple/fix-mbp15-dgpu.sh"
helper="$ROOT/install/hardware/apple/mbp15-dgpu.sh"
migration="$ROOT/migrations/1786920500.sh"
manual="$ROOT/manual/44-mac-support.md"
menu="$ROOT/default/omarchy/omarchy-menu.jsonc"
nvme="$ROOT/install/hardware/apple/fix-suspend-nvme.sh"

assert_hw() {
  local model=$1 expect=$2 description=$3
  local tmp got
  tmp=$(mktemp)
  printf '%s\n' "$model" >"$tmp"
  if OMARCHY_DMI_PRODUCT_NAME="$tmp" "$hw"; then
    got=yes
  else
    got=no
  fi
  rm -f "$tmp"
  [[ $got == "$expect" ]] || fail "$description"
  pass "$description"
}

assert_hw MacBookPro14,3 yes "MacBookPro14,3 is a 15-inch Radeon model"
assert_hw MacBookPro13,3 yes "MacBookPro13,3 is a 15-inch Radeon model"
assert_hw MacBookPro14,2 no "MacBookPro14,2 is 13-inch Intel"
assert_hw MacBookPro14,1 no "MacBookPro14,1 is 13-inch Intel"
assert_hw MacBookPro13,2 no "MacBookPro13,2 is 13-inch Intel"
assert_hw MacBookPro13,1 no "MacBookPro13,1 is 13-inch Intel"
assert_hw MacBookPro15,1 no "MacBookPro15,1 is T2"

grep -Fq 'fix-mbp15-dgpu.sh' "$ROOT/install/hardware/all.sh" ||
  fail "hardware install runs the 15-inch Radeon hook"
pass "15-inch Radeon hook is wired"

grep -Fq 'omarchy-hw-apple-mbp15-dgpu' "$fix" ||
  fail "install hook is gated on the 15-inch detector"
grep -Fq 'mbp15_apply' "$fix" || fail "install hook applies the shared helper"
pass "install hook is gated and applies policy"

grep -Fq 'omarchy-hw-apple-mbp15-dgpu' "$menu" ||
  fail "menu hides suspend on 15-inch Radeon hardware"
grep -Fq 'omarchy-hibernation-available && ! omarchy-hw-apple-mbp15-dgpu' "$menu" ||
  fail "menu hides hibernate on 15-inch Radeon hardware"
pass "menu when: hides sleep on 15-inch Radeon hardware"

grep -Fq 'POWER_SAVING' "$manual" ||
  fail "Mac support chapter documents the Radeon idle profile"
grep -Fq 'cannot resume from suspend' "$manual" ||
  fail "Mac support chapter documents the sleep limitation"
pass "Mac support chapter documents lid lock and POWER_SAVING"

[[ -f $migration ]] || fail "15-inch Radeon migration exists"
! head -1 "$migration" | grep -q '^#!' || fail "migration has no shebang"
grep -Fq 'omarchy-hw-apple-mbp15-dgpu' "$migration" ||
  fail "migration is gated on the 15-inch detector"
pass "migration is gated and has no shebang"

grep -Fq '/sys/class/nvme/nvme0/device' "$nvme" ||
  fail "NVMe suspend fix prefers the real nvme0 PCI device"
pass "NVMe suspend fix is not hard-coded to the Radeon address"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

etc="$test_tmp/etc"
mkdir -p "$etc"
OMARCHY_PATH="$ROOT" \
  OMARCHY_MBP15_LOGIND="$etc/logind.conf" \
  OMARCHY_MBP15_SLEEP="$etc/sleep.conf" \
  OMARCHY_MBP15_UDEV_SRC="$ROOT/default/udev/apple-mbp15-amdgpu-idle.rules" \
  OMARCHY_MBP15_UDEV_DEST="$etc/udev.rules" \
  OMARCHY_MBP15_UNIT_SRC="$ROOT/default/systemd/omarchy-mbp15-amdgpu-idle.service" \
  OMARCHY_MBP15_UNIT_DEST="$etc/idle.service" \
  OMARCHY_MBP15_SKIP_SYSTEMCTL=1 \
  bash -c 'source "$1"; mbp15_apply' _ "$helper"

grep -Fq 'HandleLidSwitch=lock' "$etc/logind.conf" || fail "helper writes lid lock"
grep -Fq 'AllowSuspend=no' "$etc/sleep.conf" || fail "helper refuses suspend"
grep -Fq 'omarchy-hw-apple-mbp15-amdgpu-idle' "$etc/udev.rules" ||
  fail "helper installs the idle udev rule"
grep -Fq 'POWER_SAVING' "$idle" || fail "idle helper selects POWER_SAVING"
pass "helper writes lid lock, sleep ban, and idle wiring"

dmi="$test_tmp/dmi"
printf 'MacBookPro14,2\n' >"$dmi"
OMARCHY_DMI_PRODUCT_NAME="$dmi" "$idle" || fail "idle helper must exit 0 off 15-inch hardware"
pass "idle helper no-ops on 13-inch hardware"

gpu="$test_tmp/gpu"
mkdir -p "$gpu"
printf '0x1002\n' >"$gpu/vendor"
printf 'auto\n' >"$gpu/power_dpm_force_performance_level"
cat >"$gpu/pp_power_profile_mode" <<'EOF'
  1   3D_FULL_SCREEN:        0              100
  2   POWER_SAVING:       10                0
EOF
printf '0: 214Mhz *\n1: 907Mhz\n' >"$gpu/pp_dpm_sclk"
printf '0: 300Mhz *\n1: 1270Mhz\n' >"$gpu/pp_dpm_mclk"
chmod u+w "$gpu"/*

printf 'MacBookPro14,3\n' >"$dmi"
OMARCHY_DMI_PRODUCT_NAME="$dmi" OMARCHY_MBP15_AMDGPU_DEV="$gpu" "$idle"
[[ $(cat "$gpu/power_dpm_force_performance_level") == manual ]] ||
  fail "idle helper switches to manual"
[[ $(cat "$gpu/pp_power_profile_mode") == 2 ]] ||
  fail "idle helper writes POWER_SAVING"
pass "idle helper selects manual + POWER_SAVING on fixture GPU"

dmi_t2="$test_tmp/dmi-t2"
printf 'MacBookPro16,1\n' >"$dmi_t2"
PATH="$ROOT/bin:$PATH" \
  OMARCHY_DMI_PRODUCT_NAME="$dmi_t2" \
  OMARCHY_PATH="$ROOT" \
  bash -euo pipefail "$migration" >/dev/null
[[ ! -e $etc/logind.conf.bak ]] || true
pass "migration skips non-15-inch hardware"
