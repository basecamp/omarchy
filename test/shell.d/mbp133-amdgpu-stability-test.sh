#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-mbp133-amdgpu.sh"
helper="$ROOT/install/hardware/apple/mbp133-amdgpu-stability"
monitor="$ROOT/install/hardware/apple/mbp133-amdgpu-stability-monitor"
all="$ROOT/install/hardware/all.sh"
migration="$ROOT/migrations/1788508181.sh"
manual="$ROOT/manual/44-mac-support.md"

grep -q 'apple/fix-mbp133-amdgpu.sh' "$all" ||
  fail "MacBookPro13,3 Radeon fix runs during hardware setup"
pass "MacBookPro13,3 Radeon fix runs during hardware setup"

grep -Fq 'pins only the VRAM clock to its highest performance level' "$manual" ||
  fail "Mac support chapter documents the Radeon stability tradeoff"
pass "Mac support chapter documents the Radeon stability tradeoff"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
dmi_product="$test_tmp/product_name"
pci_devices="$test_tmp/sys/bus/pci/devices"
gpu="$pci_devices/0000:01:00.0"
installed_helper="$test_tmp/etc/omarchy/hardware/mbp133-amdgpu-stability"
installed_monitor="$test_tmp/etc/omarchy/hardware/mbp133-amdgpu-stability-monitor"
unit_file="$test_tmp/etc/systemd/system/omarchy-mbp133-amdgpu-stability.service"
timer_file="$test_tmp/etc/systemd/system/omarchy-mbp133-amdgpu-stability.timer"
mkdir -p "$stub_bin" "$gpu" "$(dirname "$unit_file")"
: >"$calls"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

cat >"$stub_bin/systemctl" <<'SH'
#!/bin/bash

printf 'systemctl' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

cat >"$stub_bin/omarchy-state" <<'SH'
#!/bin/bash

printf 'omarchy-state' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

cat >"$stub_bin/logger" <<'SH'
#!/bin/bash
:
SH

cat >"$stub_bin/install" <<'SH'
#!/bin/bash

mode=0755
while (($#)); do
  case "$1" in
    -D) shift ;;
    -m) mode=$2; shift 2 ;;
    *) break ;;
  esac
done
source=$1
target=$2
mkdir -p "$(dirname "$target")"
cp "$source" "$target"
chmod "$mode" "$target"
SH

chmod +x "$stub_bin"/*

provide_gpu() {
  mkdir -p "$gpu"
  printf '0x1002\n' >"$gpu/vendor"
  printf '0x67ef\n' >"$gpu/device"
  printf '0x106b\n' >"$gpu/subsystem_vendor"
  printf '0x0160\n' >"$gpu/subsystem_device"
  printf 'auto\n' >"$gpu/power_dpm_force_performance_level"
  printf '0: 214Mhz *\n1: 320Mhz\n7: 907Mhz\n' >"$gpu/pp_dpm_sclk"
  printf '0: 300Mhz *\n1: 1270Mhz\n' >"$gpu/pp_dpm_mclk"
  printf '0: 2.5GT/s, x8 *\n1: 8.0GT/s, x16\n' >"$gpu/pp_dpm_pcie"
}

invoke_leaf() {
  PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_INSTALL="$ROOT/install" \
    OMARCHY_MBP133_DMI_PRODUCT="$dmi_product" \
    OMARCHY_MBP133_PCI_DEVICES="$pci_devices" \
    OMARCHY_MBP133_HELPER="$installed_helper" \
    OMARCHY_MBP133_MONITOR="$installed_monitor" \
    OMARCHY_MBP133_UNIT="$unit_file" \
    OMARCHY_MBP133_TIMER="$timer_file" \
    bash -euo pipefail -c 'source "$1"' bash "$leaf" >/dev/null
}

provide_gpu
printf 'MacBookPro13,3\n' >"$dmi_product"
invoke_leaf

[[ -x $installed_helper ]] || fail "Radeon workaround helper is installed"
[[ -x $installed_monitor ]] || fail "Radeon watchdog is installed"
grep -Fxq "ExecStartPre=$installed_helper" "$unit_file" ||
  fail "Radeon service applies the mask before starting its watchdog"
grep -Fxq "ExecStart=$installed_monitor" "$unit_file" ||
  fail "Radeon service continuously watches for driver resets"
grep -Fxq 'Before=display-manager.service' "$unit_file" ||
  fail "Radeon workaround applies before the display manager"
[[ ! -e $timer_file ]] || fail "Radeon workaround removes the vulnerable delayed timer"
grep -Fq 'sleep 0.25' "$monitor" || fail "Radeon watchdog polls rapidly during session startup"
grep -Fq 'sleep 2' "$monitor" || fail "Radeon watchdog backs off after session startup"
grep -Fq 'mclk_is_highest' "$monitor" || fail "Radeon watchdog writes only after a mask reset"
grep -Fq $'systemctl\tenable\tomarchy-mbp133-amdgpu-stability.service' "$calls" ||
  fail "Radeon service is enabled"
grep -Fq $'systemctl\tdisable\t--now\tomarchy-mbp133-amdgpu-stability.timer' "$calls" ||
  fail "Radeon setup disables the obsolete timer"
pass "exact MacBookPro13,3 Radeon hardware installs the no-gap watchdog"

apply_stub="$stub_bin/apply-mclk"
cat >"$apply_stub" <<SH
#!/bin/bash
echo apply >>"$test_tmp/watchdog-applies"
printf 'manual\n' >"$gpu/power_dpm_force_performance_level"
printf '0: 300Mhz\n1: 1270Mhz *\n' >"$gpu/pp_dpm_mclk"
SH
chmod +x "$apply_stub"

provide_gpu
: >"$test_tmp/watchdog-applies"
(
  sleep 0.4
  printf 'auto\n' >"$gpu/power_dpm_force_performance_level"
  printf '0: 300Mhz *\n1: 1270Mhz\n' >"$gpu/pp_dpm_mclk"
) &
reset_pid=$!
set +e
PATH="$stub_bin:$PATH" \
  OMARCHY_MBP133_DMI_PRODUCT="$dmi_product" \
  OMARCHY_MBP133_PCI_DEVICES="$pci_devices" \
  OMARCHY_MBP133_APPLY_HELPER="$apply_stub" \
  timeout 1.2 "$installed_monitor" >/dev/null 2>&1
monitor_status=$?
set -e
wait "$reset_pid"
(( monitor_status == 124 )) || fail "Radeon watchdog stays active"
(( $(wc -l <"$test_tmp/watchdog-applies") >= 2 )) ||
  fail "Radeon watchdog catches a compositor-style mask reset"
pass "Radeon watchdog closes the compositor reset window"

OMARCHY_MBP133_DMI_PRODUCT="$dmi_product" \
  OMARCHY_MBP133_PCI_DEVICES="$pci_devices" \
  OMARCHY_MBP133_VERIFY_DPM=0 \
  "$installed_helper" >/dev/null

[[ $(<"$gpu/power_dpm_force_performance_level") == manual ]] ||
  fail "Radeon helper selects manual DPM masks"
[[ $(<"$gpu/pp_dpm_sclk") == "0 1 7" ]] || fail "Radeon core retains every clock level"
[[ $(<"$gpu/pp_dpm_mclk") == 1 ]] || fail "Radeon VRAM is pinned to its highest level"
[[ $(<"$gpu/pp_dpm_pcie") == "0 1" ]] || fail "Radeon PCIe retains every link level"
pass "Radeon helper pins only the highest VRAM clock"

printf 'MacBookPro14,3\n' >"$dmi_product"
rm -f "$unit_file" "$timer_file" "$installed_helper" "$installed_monitor"
: >"$calls"
invoke_leaf
[[ ! -e $unit_file && ! -e $timer_file && ! -e $installed_monitor ]] ||
  fail "other MacBook models are left unchanged"
[[ ! -s $calls ]] || fail "other MacBook models invoke no privileged commands"
pass "Radeon workaround is limited to MacBookPro13,3"

printf 'MacBookPro13,3\n' >"$dmi_product"
printf '0x0161\n' >"$gpu/subsystem_device"
: >"$calls"
invoke_leaf
[[ ! -e $unit_file && ! -e $timer_file && ! -e $installed_monitor ]] ||
  fail "different Radeon boards are left unchanged"
[[ ! -s $calls ]] || fail "different Radeon boards invoke no privileged commands"
pass "Radeon workaround is limited to the validated Apple board"

provide_gpu
: >"$calls"
PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_INSTALL="$ROOT/install" \
  OMARCHY_MBP133_DMI_PRODUCT="$dmi_product" \
  OMARCHY_MBP133_PCI_DEVICES="$pci_devices" \
  OMARCHY_MBP133_HELPER="$installed_helper" \
  OMARCHY_MBP133_MONITOR="$installed_monitor" \
  OMARCHY_MBP133_UNIT="$unit_file" \
  OMARCHY_MBP133_TIMER="$timer_file" \
  bash -euo pipefail "$migration" >/dev/null

grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "Radeon migration asks for the reboot that activates the watchdog"
pass "Radeon migration installs the workaround and asks for a reboot"
