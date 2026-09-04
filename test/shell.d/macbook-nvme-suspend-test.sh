#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-suspend-nvme.sh"
helper="$ROOT/install/hardware/apple/macbook-nvme-suspend"
migration="$ROOT/migrations/1788503592.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
dmi_product="$test_tmp/product_name"
nvme_sysfs="$test_tmp/sys/class/nvme"
installed_helper="$test_tmp/etc/omarchy/hardware/macbook-nvme-suspend"
unit_file="$test_tmp/etc/systemd/system/omarchy-nvme-suspend-fix.service"
mkdir -p "$stub_bin" "$(dirname "$unit_file")"
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

invoke_leaf() {
  PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_INSTALL="$ROOT/install" \
    OMARCHY_MACBOOK_DMI_PRODUCT="$dmi_product" \
    OMARCHY_MACBOOK_ROOT_DISK="${TEST_ROOT_DISK:-nvme0n1}" \
    OMARCHY_MACBOOK_NVME_SYSFS="$nvme_sysfs" \
    OMARCHY_MACBOOK_NVME_HELPER="$installed_helper" \
    OMARCHY_MACBOOK_NVME_UNIT="$unit_file" \
    bash -euo pipefail -c 'source "$1"' bash "$leaf" >/dev/null
}

mkdir -p "$nvme_sysfs/nvme0/device" "$nvme_sysfs/nvme1/device"
printf '1\n' >"$nvme_sysfs/nvme0/device/d3cold_allowed"
printf '1\n' >"$nvme_sysfs/nvme1/device/d3cold_allowed"
printf 'MacBookPro13,3\n' >"$dmi_product"
invoke_leaf

[[ -x $installed_helper ]] || fail "MacBook NVMe helper is installed"
grep -Fxq "ExecStart=$installed_helper" "$unit_file" ||
  fail "NVMe service executes the installed helper"
! grep -q '0000.*01.*00.0' "$unit_file" ||
  fail "NVMe service never hard-codes the Radeon PCI address"
grep -Fq $'systemctl\tenable\t--now\tomarchy-nvme-suspend-fix.service' "$calls" ||
  fail "NVMe service is enabled and applied immediately"
pass "MacBookPro13,3 installs a class-based NVMe suspend service"

OMARCHY_MACBOOK_NVME_SYSFS="$nvme_sysfs" "$installed_helper" >/dev/null
[[ $(<"$nvme_sysfs/nvme0/device/d3cold_allowed") == 0 ]] ||
  fail "first NVMe controller has D3cold disabled"
[[ $(<"$nvme_sysfs/nvme1/device/d3cold_allowed") == 0 ]] ||
  fail "second NVMe controller has D3cold disabled"
pass "NVMe helper applies the setting to every actual controller"

# An external root does not need an internal-NVMe boot workaround. Remove an
# old fixed-BDF unit so it cannot keep changing the Radeon at 01:00.0.
cat >"$unit_file" <<'EOF'
[Service]
ExecStart=/bin/bash -c 'echo 0 > /sys/bus/pci/devices/0000\:01\:00.0/d3cold_allowed'
EOF
: >"$calls"
TEST_ROOT_DISK=sda invoke_leaf
[[ ! -e $unit_file ]] || fail "external root removes the active NVMe unit"
[[ -f $unit_file.disabled-non-nvme-root ]] ||
  fail "external root preserves the stale unit as a disabled backup"
grep -Fq $'systemctl\tdisable\t--now\tomarchy-nvme-suspend-fix.service' "$calls" ||
  fail "external root disables the stale NVMe unit"
pass "external USB root disables the mis-targeted NVMe workaround"

: >"$calls"
printf 'ThinkPad X1\n' >"$dmi_product"
rm -f "$unit_file" "$unit_file.disabled-non-nvme-root" "$installed_helper"
invoke_leaf
[[ ! -e $unit_file && ! -e $installed_helper ]] ||
  fail "non-Apple hardware is left unchanged"
[[ ! -s $calls ]] || fail "non-Apple hardware invokes no privileged commands"
pass "unrelated hardware skips the MacBook NVMe fix"

printf 'MacBookPro13,3\n' >"$dmi_product"
mkdir -p "$(dirname "$unit_file")"
cat >"$unit_file" <<'EOF'
[Service]
ExecStart=/bin/bash -c 'echo 0 > /sys/bus/pci/devices/0000\:01\:00.0/d3cold_allowed'
EOF
: >"$calls"

PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_INSTALL="$ROOT/install" \
  OMARCHY_MACBOOK_DMI_PRODUCT="$dmi_product" \
  OMARCHY_MACBOOK_ROOT_DISK=nvme0n1 \
  OMARCHY_MACBOOK_NVME_SYSFS="$nvme_sysfs" \
  OMARCHY_MACBOOK_NVME_HELPER="$installed_helper" \
  OMARCHY_MACBOOK_NVME_UNIT="$unit_file" \
  bash -euo pipefail "$migration" >/dev/null

grep -Fxq "ExecStart=$installed_helper" "$unit_file" ||
  fail "migration replaces the fixed-BDF service"
! grep -q '0000.*01.*00.0' "$unit_file" ||
  fail "migration removes the Radeon PCI address"
pass "migration repairs an existing mis-targeted service"
