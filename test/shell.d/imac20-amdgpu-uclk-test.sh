#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

detector="$ROOT/bin/omarchy-hw-imac20-amdgpu-uclk"
enabler="$ROOT/bin/omarchy-amdgpu-uclk-enable"
installer="$ROOT/install/hardware/apple/fix-imac20-amdgpu-uclk.sh"
migration="$ROOT/migrations/1788524636.sh"

grep -Fq 'apple/fix-imac20-amdgpu-uclk.sh' "$ROOT/install/hardware/all.sh" ||
  fail "the iMac AMDGPU workaround runs during hardware setup"
pass "the iMac AMDGPU workaround runs during hardware setup"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

dmi_file="$test_tmp/product_name"
pci_devices="$test_tmp/pci"
gpu_path="$pci_devices/0000:03:00.0"
mkdir -p "$gpu_path"

write_hardware() {
  printf '%s\n' "${1:-iMac20,2}" >"$dmi_file"
  printf '%s\n' "${2:-0x1002}" >"$gpu_path/vendor"
  printf '%s\n' "${3:-0x7319}" >"$gpu_path/device"
  printf '%s\n' "${4:-0x106b}" >"$gpu_path/subsystem_vendor"
  printf '%s\n' "${5:-0x021b}" >"$gpu_path/subsystem_device"
}

detect_gpu() {
  OMARCHY_DMI_PRODUCT_NAME="$dmi_file" \
    OMARCHY_PCI_DEVICES_PATH="$pci_devices" \
    "$detector"
}

write_hardware
[[ $(detect_gpu) == "$gpu_path" ]] || fail "the affected iMac GPU is detected"
pass "the affected iMac GPU is detected"

write_hardware "iMac20,1"
! detect_gpu >/dev/null || fail "a different iMac model is rejected"
write_hardware "iMac20,2" "0x1002" "0x7319" "0x106b" "0x0219"
! detect_gpu >/dev/null || fail "a different Apple Radeon subsystem is rejected"
pass "nearby Apple Radeon hardware is not matched"

write_hardware
cmdline_file="$test_tmp/cmdline"
features_file="$gpu_path/pp_features"
printf '%s\n' 'quiet amdgpu.ppfeaturemask=0xfff7bffd splash' >"$cmdline_file"
printf '%s\n%s\n' 'features high: 0x00000662' 'features low: 0xa3d9acb3' >"$features_file"
features_writer="$test_tmp/write-features"
cat >"$features_writer" <<'SH'
#!/bin/bash
[[ $1 == "0x00000662a3d9afbb" ]] || exit 1
printf '%s\n%s\n' 'features high: 0x00000662' 'features low: 0xa3d9afbb' >"$2"
SH
chmod +x "$features_writer"

PATH="$ROOT/bin:$PATH" \
  OMARCHY_ALLOW_NON_ROOT_TEST=1 \
  OMARCHY_AMDGPU_FEATURES_WRITER="$features_writer" \
  OMARCHY_DMI_PRODUCT_NAME="$dmi_file" \
  OMARCHY_PCI_DEVICES_PATH="$pci_devices" \
  OMARCHY_KERNEL_CMDLINE="$cmdline_file" \
  "$enabler" >/dev/null

grep -Fxq 'features low: 0xa3d9afbb' "$features_file" ||
  fail "the runtime helper restores UCLK and its voltage-scaling features" "$(cat "$features_file")"
pass "the runtime helper restores UCLK and its voltage-scaling features"

printf '%s\n' 'quiet splash' >"$cmdline_file"
printf '%s\n%s\n' 'features high: 0x00000662' 'features low: 0xa3d9acb3' >"$features_file"
! PATH="$ROOT/bin:$PATH" \
  OMARCHY_ALLOW_NON_ROOT_TEST=1 \
  OMARCHY_DMI_PRODUCT_NAME="$dmi_file" \
  OMARCHY_PCI_DEVICES_PATH="$pci_devices" \
  OMARCHY_KERNEL_CMDLINE="$cmdline_file" \
  "$enabler" >/dev/null 2>&1 || fail "the runtime helper requires the safe boot mask"
grep -Fq 'features low: 0xa3d9acb3' "$features_file" || fail "a rejected runtime update leaves features unchanged"
pass "the runtime helper refuses to run without the safe boot mask"

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
limine_conf="$test_tmp/etc/limine-entry-tool.d/imac20-amdgpu-uclk.conf"
systemd_unit="$test_tmp/etc/systemd/system/omarchy-imac20-amdgpu-uclk.service"
mkdir -p "$stub_bin"
: >"$calls"

cat >"$stub_bin/systemctl" <<'SH'
#!/bin/bash
printf 'systemctl' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH
chmod +x "$stub_bin/systemctl"

PATH="$stub_bin:$ROOT/bin:$PATH" \
  TEST_LOG="$calls" \
  OMARCHY_DMI_PRODUCT_NAME="$dmi_file" \
  OMARCHY_PCI_DEVICES_PATH="$pci_devices" \
  OMARCHY_IMAC20_AMDGPU_LIMINE_CONF="$limine_conf" \
  OMARCHY_IMAC20_AMDGPU_SYSTEMD_UNIT="$systemd_unit" \
  bash -euo pipefail "$installer" >/dev/null

grep -Fq 'amdgpu.ppfeaturemask=0xfff7bffd' "$limine_conf" || fail "the installer adds the safe boot mask"
grep -Fq 'After=display-manager.service' "$systemd_unit" || fail "the service waits for the display manager"
grep -Fq 'ExecStart=/usr/bin/omarchy-amdgpu-uclk-enable' "$systemd_unit" || fail "the service runs the packaged helper"
grep -Fxq $'systemctl\tdaemon-reload' "$calls" || fail "the installer reloads systemd"
grep -Fxq $'systemctl\tenable\tomarchy-imac20-amdgpu-uclk.service' "$calls" || fail "the installer enables the workaround"
pass "fresh installs configure both stages of the workaround"

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

chmod +x "$stub_bin/sudo" "$stub_bin/limine-mkinitcpio"
marker="$test_tmp/migration-complete"
: >"$calls"

PATH="$stub_bin:$PATH" \
  TEST_LOG="$calls" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_DMI_PRODUCT_NAME="$dmi_file" \
  OMARCHY_PCI_DEVICES_PATH="$pci_devices" \
  OMARCHY_IMAC20_AMDGPU_LIMINE_CONF="$limine_conf" \
  OMARCHY_IMAC20_AMDGPU_SYSTEMD_UNIT="$systemd_unit" \
  OMARCHY_IMAC20_AMDGPU_MARKER="$marker" \
  OMARCHY_IMAC20_AMDGPU_SYSTEM_PATH="$stub_bin:$ROOT/bin:/usr/bin" \
  bash -euo pipefail "$migration" >/dev/null

grep -Fq $'sudo\tlimine-mkinitcpio' "$calls" || fail "the migration rebuilds the boot image"
[[ -f $marker ]] || fail "the migration records machine-wide completion"
pass "existing affected installs receive the workaround"

: >"$calls"
PATH="$stub_bin:$PATH" \
  TEST_LOG="$calls" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_DMI_PRODUCT_NAME="$dmi_file" \
  OMARCHY_PCI_DEVICES_PATH="$pci_devices" \
  OMARCHY_IMAC20_AMDGPU_LIMINE_CONF="$limine_conf" \
  OMARCHY_IMAC20_AMDGPU_SYSTEMD_UNIT="$systemd_unit" \
  OMARCHY_IMAC20_AMDGPU_MARKER="$marker" \
  OMARCHY_IMAC20_AMDGPU_SYSTEM_PATH="$stub_bin:$ROOT/bin:/usr/bin" \
  bash -euo pipefail "$migration" >/dev/null

[[ ! -s $calls ]] || fail "the migration is machine-idempotent" "$(cat "$calls")"
pass "the migration is machine-idempotent"
