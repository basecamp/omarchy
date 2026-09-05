#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-brcmfmac-suspend.sh"
helper="$ROOT/bin/omarchy-hw-brcmfmac-suspend"
service="$ROOT/install/hardware/apple/omarchy-brcmfmac-suspend.service"
all="$ROOT/install/hardware/all.sh"
migration="$ROOT/migrations/1786907783.sh"

grep -q 'apple/fix-brcmfmac-suspend.sh' "$all" ||
  fail "the BCM4350 suspend fix runs during hardware setup"
grep -Fx 'Before=sleep.target' "$service" >/dev/null ||
  fail "the BCM4350 service detaches the device before sleep"
grep -Fx 'StopWhenUnneeded=yes' "$service" >/dev/null ||
  fail "the BCM4350 service stops after the sleep transaction"
grep -Fx 'ConditionPathExists=/sys/bus/pci/drivers/brcmfmac' "$service" >/dev/null ||
  fail "the BCM4350 service only runs when the driver is available"
grep -Fx 'ExecStart=/usr/bin/omarchy-hw-brcmfmac-suspend pre' "$service" >/dev/null ||
  fail "the BCM4350 service runs the pre-sleep recovery helper"
grep -Fx 'ExecStop=/usr/bin/omarchy-hw-brcmfmac-suspend post' "$service" >/dev/null ||
  fail "the BCM4350 service runs the post-wake recovery helper"
grep -Fx 'WantedBy=sleep.target' "$service" >/dev/null ||
  fail "the BCM4350 service joins every sleep transaction"
pass "the BCM4350 service resets the driver around sleep"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
target="$test_tmp/etc/systemd/system/omarchy-brcmfmac-suspend.service"
enabled="$test_tmp/enabled"
mkdir -p "$stub_bin" "$test_tmp/dmi"

cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash

if [[ -n ${WIFI_ID:-} ]]; then
  echo "02:00.0 Network controller [0280]: Broadcom Inc. Wireless [14e4:$WIFI_ID]"
fi
for _ in {1..4096}; do
  echo '00:00.0 Host bridge [0600]: Filler Device [ffff:0000]'
done
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

cat >"$stub_bin/systemctl" <<'SH'
#!/bin/bash

if [[ $1 == "is-enabled" ]]; then
  [[ -e $ENABLED_MARKER ]]
  exit
fi

printf 'systemctl' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
[[ $1 != "enable" ]] || touch "$ENABLED_MARKER"
SH

chmod +x "$stub_bin"/*

driver_path="$test_tmp/sys/bus/pci/drivers/brcmfmac"
device_root="$test_tmp/sys/bus/pci/devices"
state_file="$test_tmp/run/omarchy-brcmfmac-suspend.devices"
pci_address="0000:02:00.0"
mkdir -p "$driver_path" "$device_root/$pci_address"
printf '0x14e4' >"$device_root/$pci_address/vendor"
printf '0x43a3' >"$device_root/$pci_address/device"
ln -s "$device_root/$pci_address" "$driver_path/$pci_address"
ln -s "$driver_path" "$device_root/$pci_address/driver"
: >"$driver_path/unbind"
: >"$driver_path/bind"

OMARCHY_BRCMFMAC_DRIVER_PATH="$driver_path" \
  OMARCHY_BRCMFMAC_DEVICE_ROOT="$device_root" \
  OMARCHY_BRCMFMAC_SUSPEND_STATE="$state_file" \
  "$helper" pre
[[ $(<"$driver_path/unbind") == "$pci_address" ]] ||
  fail "the pre-sleep helper unbinds the BCM4350 PCI device"
[[ $(<"$state_file") == "$pci_address" ]] ||
  fail "the pre-sleep helper records the device for wake"
pass "the pre-sleep helper detaches the affected PCI device"

rm "$driver_path/$pci_address" "$device_root/$pci_address/driver"
OMARCHY_BRCMFMAC_DRIVER_PATH="$driver_path" \
  OMARCHY_BRCMFMAC_DEVICE_ROOT="$device_root" \
  OMARCHY_BRCMFMAC_SUSPEND_STATE="$state_file" \
  "$helper" post
[[ $(<"$driver_path/bind") == "$pci_address" ]] ||
  fail "the post-wake helper rebinds the BCM4350 PCI device"
[[ ! -e $state_file ]] || fail "the post-wake helper clears its device state"
pass "the post-wake helper reattaches the affected PCI device"

missing_address="0000:04:00.0"
printf '%s\n' "$missing_address" >"$state_file"
if OMARCHY_BRCMFMAC_DRIVER_PATH="$driver_path" \
  OMARCHY_BRCMFMAC_DEVICE_ROOT="$device_root" \
  OMARCHY_BRCMFMAC_SUSPEND_STATE="$state_file" \
  "$helper" post 2>/dev/null; then
  fail "the post-wake helper reports a missing PCI device"
fi
[[ -e $state_file ]] || fail "failed recovery keeps its device state for retry"
rm "$state_file"
pass "failed recovery remains visible and retryable"

other_address="0000:03:00.0"
mkdir -p "$device_root/$other_address"
printf '0x14e4' >"$device_root/$other_address/vendor"
printf '0x43ba' >"$device_root/$other_address/device"
ln -s "$device_root/$other_address" "$driver_path/$other_address"
: >"$driver_path/unbind"
if OMARCHY_BRCMFMAC_DRIVER_PATH="$driver_path" \
  OMARCHY_BRCMFMAC_DEVICE_ROOT="$device_root" \
  OMARCHY_BRCMFMAC_SUSPEND_STATE="$state_file" \
  "$helper" pre 2>/dev/null; then
  fail "the pre-sleep helper rejects a different Broadcom PCI device"
fi
[[ ! -s $driver_path/unbind ]] || fail "the pre-sleep helper leaves other devices bound"
pass "the pre-sleep helper only detaches BCM4350 hardware"

run_leaf() {
  local vendor="$1" wifi_id="${2:-}"
  local script="$test_tmp/leaf.sh"

  rm -rf "$test_tmp/etc"
  mkdir -p "$test_tmp/etc"
  printf '%s' "$vendor" >"$test_tmp/dmi/sys_vendor"
  : >"$calls"

  sed \
    -e "s|/sys/class/dmi/id/sys_vendor|$test_tmp/dmi/sys_vendor|g" \
    -e "s|/etc/systemd/system/omarchy-brcmfmac-suspend.service|$target|g" \
    "$leaf" >"$script"

  WIFI_ID="$wifi_id" PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_PATH="$ROOT" ENABLED_MARKER="$enabled" \
    bash -eE -o pipefail -c 'source "$1"' bash "$script" </dev/null
}

run_leaf "Apple Inc." 43a3 >/dev/null
cmp -s "$service" "$target" ||
  fail "Apple BCM4350 setup installs the sleep service"
grep -Fq $'systemctl\tenable\tomarchy-brcmfmac-suspend.service' "$calls" ||
  fail "Apple BCM4350 setup enables the sleep service" "$(cat "$calls")"
pass "Apple BCM4350 setup installs and enables the sleep service"

run_leaf "Apple Inc." 43ba >/dev/null
[[ ! -e $target ]] || fail "other Apple Broadcom radios are left alone"
[[ ! -s $calls ]] || fail "other Apple Broadcom radios change no system state" "$(cat "$calls")"
pass "other Apple Broadcom radios are left alone"

run_leaf "LENOVO" 43a3 >/dev/null
[[ ! -e $target ]] || fail "non-Apple BCM4350 hardware is left alone"
[[ ! -s $calls ]] || fail "non-Apple BCM4350 hardware changes no system state" "$(cat "$calls")"
pass "non-Apple BCM4350 hardware is left alone"

run_migration() {
  local vendor="$1" wifi_id="${2:-}"

  printf '%s' "$vendor" >"$test_tmp/dmi/sys_vendor"
  : >"$calls"

  WIFI_ID="$wifi_id" PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    ENABLED_MARKER="$enabled" OMARCHY_PATH="$ROOT" \
    OMARCHY_BRCMFMAC_DMI_VENDOR="$test_tmp/dmi/sys_vendor" \
    OMARCHY_BRCMFMAC_SUSPEND_SERVICE_SOURCE="$service" \
    OMARCHY_BRCMFMAC_SUSPEND_SERVICE_TARGET="$target" \
    bash -euo pipefail "$migration" >/dev/null
}

rm -rf "$test_tmp/etc"
rm -f "$enabled"
run_migration "Apple Inc." 43a3
cmp -s "$service" "$target" ||
  fail "the migration installs the service on an existing Apple BCM4350 system"
[[ -e $enabled ]] || fail "the migration enables the BCM4350 sleep service"
pass "the migration repairs an existing Apple BCM4350 system"

run_migration "Apple Inc." 43a3
[[ ! -s $calls ]] || fail "the migration is idempotent" "$(cat "$calls")"
pass "the migration leaves a repaired system untouched"

rm -rf "$test_tmp/etc"
rm -f "$enabled"
run_migration "Apple Inc." 43ba
[[ ! -e $target ]] || fail "the migration skips other Apple Broadcom radios"
[[ ! -s $calls ]] || fail "the migration escalates nothing on unaffected hardware" "$(cat "$calls")"
pass "the migration skips unaffected hardware"
