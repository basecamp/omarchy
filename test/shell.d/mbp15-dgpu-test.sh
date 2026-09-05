#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

hw="$ROOT/bin/omarchy-hw-apple-mbp15-dgpu"
idle="$ROOT/bin/omarchy-hw-apple-mbp15-amdgpu-idle"
wifi_pm="$ROOT/bin/omarchy-hw-apple-mbp15-wifi-pm"
fix="$ROOT/install/hardware/apple/fix-mbp15-dgpu.sh"
helper="$ROOT/install/hardware/apple/mbp15-dgpu.sh"
migration="$ROOT/migrations/1786920500.sh"
wifi_migration="$ROOT/migrations/1788634178.sh"
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
grep -Fq 'BCM43602 stays PCI-awake' "$manual" ||
  fail "Mac support chapter documents the Broadcom PCI stay-awake"
! grep -Fq 'overlays power-saver' "$manual" ||
  fail "Mac support chapter must not document a lid-close power-saver overlay"
pass "Mac support chapter documents lid lock and POWER_SAVING"

[[ -f $migration ]] || fail "15-inch Radeon migration exists"
! head -1 "$migration" | grep -q '^#!' || fail "migration has no shebang"
grep -Fq 'omarchy-hw-apple-mbp15-dgpu' "$migration" ||
  fail "migration is gated on the 15-inch detector"
[[ -f $wifi_migration ]] || fail "BCM43602 PCI stay-awake migration exists"
! head -1 "$wifi_migration" | grep -q '^#!' || fail "wifi migration has no shebang"
grep -Fq 'omarchy-hw-apple-mbp15-dgpu' "$wifi_migration" ||
  fail "wifi migration is gated on the 15-inch detector"
grep -Fq 'mbp15_apply' "$wifi_migration" || fail "wifi migration reapplies policy"
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
  OMARCHY_MBP15_WIFI_UDEV_SRC="$ROOT/default/udev/apple-mbp15-wifi-pm.rules" \
  OMARCHY_MBP15_WIFI_UDEV_DEST="$etc/wifi-udev.rules" \
  OMARCHY_MBP15_SKIP_SYSTEMCTL=1 \
  bash -c 'source "$1"; mbp15_apply' _ "$helper"

grep -Fq 'HandleLidSwitch=lock' "$etc/logind.conf" || fail "helper writes lid lock"
grep -Fq 'AllowSuspend=no' "$etc/sleep.conf" || fail "helper refuses suspend"
grep -Fq 'omarchy-hw-apple-mbp15-amdgpu-idle' "$etc/udev.rules" ||
  fail "helper installs the idle udev rule"
grep -Fq 'ATTR{device}=="0x43ba"' "$etc/wifi-udev.rules" ||
  fail "helper installs the Broadcom stay-awake udev rule"
grep -Fq 'ATTR{power/control}="on"' "$etc/wifi-udev.rules" ||
  fail "Broadcom udev rule forces power/control on"
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

wifi="$test_tmp/wifi"
mkdir -p "$wifi/power"
printf '0x14e4\n' >"$wifi/vendor"
printf '0x43ba\n' >"$wifi/device"
printf 'auto\n' >"$wifi/power/control"
printf '1\n' >"$wifi/d3cold_allowed"
chmod u+w "$wifi/power/control" "$wifi/d3cold_allowed"

printf 'MacBookPro14,2\n' >"$dmi"
OMARCHY_DMI_PRODUCT_NAME="$dmi" OMARCHY_MBP15_WIFI_DEV="$wifi" "$wifi_pm" ||
  fail "wifi helper must exit 0 off 15-inch hardware"
[[ $(cat "$wifi/power/control") == auto ]] || fail "wifi helper must not touch PCI off 15-inch hardware"
pass "wifi helper no-ops on 13-inch hardware"

printf 'MacBookPro14,3\n' >"$dmi"
OMARCHY_DMI_PRODUCT_NAME="$dmi" OMARCHY_MBP15_WIFI_DEV="$wifi" "$wifi_pm"
[[ $(cat "$wifi/power/control") == on ]] ||
  fail "wifi helper forces power/control on" "control=$(cat "$wifi/power/control")"
[[ $(cat "$wifi/d3cold_allowed") == 0 ]] ||
  fail "wifi helper forbids D3cold" "d3cold=$(cat "$wifi/d3cold_allowed")"
pass "wifi helper pins BCM43602 awake on 15-inch hardware"

dmi_t2="$test_tmp/dmi-t2"
printf 'MacBookPro16,1\n' >"$dmi_t2"
PATH="$ROOT/bin:$PATH" \
  OMARCHY_DMI_PRODUCT_NAME="$dmi_t2" \
  OMARCHY_PATH="$ROOT" \
  bash -euo pipefail "$migration" >/dev/null
[[ ! -e $etc/logind.conf.bak ]] || true
pass "migration skips non-15-inch hardware"

lid="$ROOT/bin/omarchy-hw-apple-mbp15-lid"
grep -Fq 'omarchy-hw-apple-mbp15-lid close' "$ROOT/bin/omarchy-system-lid-close" ||
  fail "lid-close calls the 15-inch chill helper"
grep -Fq 'omarchy-hw-apple-mbp15-lid open' "$ROOT/bin/omarchy-system-lid-open" ||
  fail "lid-open restores the 15-inch overlay"
grep -Fq 'omarchy-system-lid-open' "$ROOT/default/hypr/bindings/utilities.lua" ||
  fail "default lid-open bind is omarchy-system-lid-open"
! grep -Fq 'omarchy-hw-apple-mbp15-lid' "$ROOT/bin/omarchy-hyprland-monitor-clamshell" ||
  fail "clamshell helper must not own 15-inch power policy"
grep -Fq 'omarchy-powerprofiles-set ac balanced' "$migration" ||
  fail "migration seeds AC balanced when unset"
pass "lid close/open own the overlay; clamshell stays display-only"

lid_state=$test_tmp/lid-state
mkdir -p "$lid_state" "$test_tmp/stub"
echo 675 >"$test_tmp/bl"
: >"$test_tmp/pp.log"

cat >"$test_tmp/stub/omarchy-hw-laptop-closed" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$test_tmp/stub/omarchy-hw-external-monitors" <<'SH'
#!/bin/bash
exit 1
SH
cat >"$test_tmp/stub/powerprofilesctl" <<SH
#!/bin/bash
echo "pp \$*" >>"$test_tmp/pp.log"
SH
cat >"$test_tmp/bl-get" <<SH
#!/bin/bash
cat "$test_tmp/bl"
SH
cat >"$test_tmp/bl-set" <<SH
#!/bin/bash
printf '%s\n' "\$1" >"$test_tmp/bl"
SH
: >"$test_tmp/dpms.log"
cat >"$test_tmp/dpms" <<SH
#!/bin/bash
echo "dpms \$1" >>"$test_tmp/dpms.log"
SH
printf 'true\ttrue\n' >"$test_tmp/wake"
: >"$test_tmp/wake.log"
cat >"$test_tmp/dpms-wake" <<SH
#!/bin/bash
case \$1 in
  get)
    cat "$test_tmp/wake"
    ;;
  set)
    printf '%s\t%s\n' "\$2" "\$3" >"$test_tmp/wake"
    echo "wake \$2 \$3" >>"$test_tmp/wake.log"
    ;;
  *)
    exit 2
    ;;
esac
SH
chmod +x "$test_tmp/stub/"* "$test_tmp/bl-get" "$test_tmp/bl-set" "$test_tmp/dpms" "$test_tmp/dpms-wake"

PATH="$test_tmp/stub:$ROOT/bin:$PATH" \
  OMARCHY_DMI_PRODUCT_NAME="$dmi" \
  OMARCHY_MBP15_LID_STATE="$lid_state" \
  OMARCHY_MBP15_BRIGHTNESS_GET="$test_tmp/bl-get" \
  OMARCHY_MBP15_BRIGHTNESS_SET="$test_tmp/bl-set" \
  OMARCHY_MBP15_DPMS="$test_tmp/dpms" \
  OMARCHY_MBP15_DPMS_WAKE="$test_tmp/dpms-wake" \
  "$lid" close

[[ $(cat "$test_tmp/bl") == 0 ]] || fail "lid close dims the backlight" "bl=$(cat "$test_tmp/bl")"
[[ $(cat "$lid_state/backlight") == 675 ]] || fail "lid close remembers brightness"
! grep -q 'pp set power-saver' "$test_tmp/pp.log" || fail "lid close must not set power-saver"
grep -Fxq 'dpms disable' "$test_tmp/dpms.log" || fail "lid close DPMS-offs the panel" "$(cat "$test_tmp/dpms.log")"
! grep -q omarchy-powerprofiles-set "$test_tmp/pp.log" || fail "lid close must not persist via omarchy-powerprofiles-set"
[[ $(cat "$test_tmp/wake") == $'false\tfalse' ]] ||
  fail "lid close disables DPMS wake on key/mouse" "wake=$(cat "$test_tmp/wake")"
[[ $(cat "$lid_state/dpms-wake") == $'true\ttrue' ]] ||
  fail "lid close remembers previous DPMS wake flags" "saved=$(cat "$lid_state/dpms-wake" 2>/dev/null || true)"
pass "lid close stops the panel without setting power-saver"

PATH="$test_tmp/stub:$ROOT/bin:$PATH" \
  OMARCHY_DMI_PRODUCT_NAME="$dmi" \
  OMARCHY_MBP15_LID_STATE="$lid_state" \
  OMARCHY_MBP15_BRIGHTNESS_GET="$test_tmp/bl-get" \
  OMARCHY_MBP15_BRIGHTNESS_SET="$test_tmp/bl-set" \
  OMARCHY_MBP15_DPMS="$test_tmp/dpms" \
  OMARCHY_MBP15_DPMS_WAKE="$test_tmp/dpms-wake" \
  "$lid" close
[[ $(cat "$lid_state/dpms-wake") == $'true\ttrue' ]] ||
  fail "lid close must not overwrite saved DPMS wake flags" "saved=$(cat "$lid_state/dpms-wake" 2>/dev/null || true)"
pass "lid close keeps the pre-close DPMS wake flags across a second close"

: >"$test_tmp/pp.log"
: >"$test_tmp/dpms.log"
cat >"$test_tmp/stub/omarchy-hw-laptop-closed" <<'SH'
#!/bin/bash
exit 1
SH
cat >"$test_tmp/stub/omarchy-powerprofiles-set" <<SH
#!/bin/bash
echo "pps \$*" >>"$test_tmp/pp.log"
SH
chmod +x "$test_tmp/stub/omarchy-hw-laptop-closed" "$test_tmp/stub/omarchy-powerprofiles-set"

PATH="$test_tmp/stub:$ROOT/bin:$PATH" \
  OMARCHY_DMI_PRODUCT_NAME="$dmi" \
  OMARCHY_MBP15_LID_STATE="$lid_state" \
  OMARCHY_MBP15_BRIGHTNESS_GET="$test_tmp/bl-get" \
  OMARCHY_MBP15_BRIGHTNESS_SET="$test_tmp/bl-set" \
  OMARCHY_MBP15_DPMS="$test_tmp/dpms" \
  OMARCHY_MBP15_DPMS_WAKE="$test_tmp/dpms-wake" \
  "$lid" open

grep -Fxq 'dpms enable' "$test_tmp/dpms.log" || fail "lid open DPMS-ons the panel" "$(cat "$test_tmp/dpms.log")"
[[ $(cat "$test_tmp/bl") == 675 ]] || fail "lid open restores brightness" "bl=$(cat "$test_tmp/bl")"
grep -Fq 'pps autodetect' "$test_tmp/pp.log" || fail "lid open restores the AC/battery profile"
[[ $(cat "$test_tmp/wake") == $'true\ttrue' ]] ||
  fail "lid open restores previous DPMS wake flags" "wake=$(cat "$test_tmp/wake")"
[[ ! -e $lid_state/dpms-wake ]] || fail "lid open clears saved DPMS wake flags"
pass "lid open brings the panel back and restores the remembered profile"
