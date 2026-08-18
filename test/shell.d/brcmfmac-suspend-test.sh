#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-brcmfmac-suspend.sh"
helper="$ROOT/bin/omarchy-hw-brcmfmac-suspend"
service="$ROOT/install/hardware/apple/omarchy-brcmfmac-suspend.service"
all="$ROOT/install/hardware/all.sh"
migration="$ROOT/migrations/1787013338.sh"

grep -q 'apple/fix-brcmfmac-suspend.sh' "$all" ||
  fail "the Broadcom suspend fix runs during hardware setup"
grep -Fx 'Before=sleep.target' "$service" >/dev/null ||
  fail "the Broadcom service detaches the device before sleep"
grep -Fx 'StopWhenUnneeded=yes' "$service" >/dev/null ||
  fail "the Broadcom service stops after the sleep transaction"
grep -Fx 'ConditionPathExists=/sys/bus/pci/drivers/brcmfmac' "$service" >/dev/null ||
  fail "the Broadcom service only runs when the driver is available"
grep -Fx 'ExecStart=/usr/bin/omarchy-hw-brcmfmac-suspend pre' "$service" >/dev/null ||
  fail "the Broadcom service runs the pre-sleep recovery helper"
grep -Fx 'ExecStop=/usr/bin/omarchy-hw-brcmfmac-suspend post' "$service" >/dev/null ||
  fail "the Broadcom service runs the post-wake recovery helper"
grep -Fx 'WantedBy=sleep.target' "$service" >/dev/null ||
  fail "the Broadcom service joins every sleep transaction"
pass "the Broadcom service resets the driver around sleep"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
target="$test_tmp/etc/systemd/system/omarchy-brcmfmac-suspend.service"
enabled="$test_tmp/enabled"
mkdir -p "$stub_bin" "$test_tmp/dmi"

cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash

# Chatty like real lspci: keep writing well past the pipe buffer after the
# match, so a grep -q consumer would kill this stub with SIGPIPE and pipefail
# would read that as "no such hardware" (#6608).
if [[ -n ${WIFI_ID:-} ]]; then
  echo "03:00.0 Network controller [0280]: Broadcom Inc. Wireless [14e4:$WIFI_ID]"
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
pci_address="0000:03:00.0"

reset_pci() {
  rm -rf "$device_root" "$driver_path" "$state_file"
  mkdir -p "$device_root" "$driver_path"
  : >"$driver_path/unbind"
  : >"$driver_path/bind"
}

setup_device() {
  local address="$1" device_id="$2"
  mkdir -p "$device_root/$address" "$driver_path"
  printf '0x14e4' >"$device_root/$address/vendor"
  printf '%s' "$device_id" >"$device_root/$address/device"
  ln -sfn "$device_root/$address" "$driver_path/$address"
  ln -sfn "$driver_path" "$device_root/$address/driver"
  : >"$driver_path/unbind"
  : >"$driver_path/bind"
}

run_helper() {
  OMARCHY_BRCMFMAC_DRIVER_PATH="$driver_path" \
    OMARCHY_BRCMFMAC_DEVICE_ROOT="$device_root" \
    OMARCHY_BRCMFMAC_SUSPEND_STATE="$state_file" \
    "$helper" "$@"
}

reset_pci
setup_device "$pci_address" "0x43ba"
run_helper pre
[[ $(<"$driver_path/unbind") == "$pci_address" ]] ||
  fail "the pre-sleep helper unbinds the BCM43602 PCI device"
[[ $(<"$state_file") == "$pci_address" ]] ||
  fail "the pre-sleep helper records the device for wake"
pass "the pre-sleep helper detaches the affected PCI device"

rm -f "$driver_path/$pci_address" "$device_root/$pci_address/driver"
run_helper post
[[ $(<"$driver_path/bind") == "$pci_address" ]] ||
  fail "the post-wake helper rebinds the BCM43602 PCI device"
[[ ! -e $state_file ]] || fail "the post-wake helper clears its device state"
pass "the post-wake helper reattaches the affected PCI device"

missing_address="0000:04:00.0"
printf '%s\n' "$missing_address" >"$state_file"
if run_helper post 2>/dev/null; then
  fail "the post-wake helper reports a missing PCI device"
fi
[[ -e $state_file ]] || fail "failed recovery keeps its device state for retry"
rm -f "$state_file"
pass "failed recovery remains visible and retryable"

other_address="0000:02:00.0"
reset_pci
setup_device "$other_address" "0x4464"
: >"$driver_path/unbind"
if run_helper pre 2>/dev/null; then
  fail "the pre-sleep helper rejects a T2-era Broadcom PCI device"
fi
[[ ! -s $driver_path/unbind ]] || fail "the pre-sleep helper leaves other devices bound"
pass "the pre-sleep helper only detaches confirmed S3-dead chips"

reset_pci
setup_device "$pci_address" "0x43a3"
run_helper pre
[[ $(<"$driver_path/unbind") == "$pci_address" ]] ||
  fail "the pre-sleep helper also detaches BCM4350"
pass "the pre-sleep helper also detaches BCM4350"

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

for wifi_id in 43ba 43bb 43bc 43a3; do
  run_leaf "Apple Inc." "$wifi_id" >/dev/null
  cmp -s "$service" "$target" ||
    fail "Apple setup installs the sleep service" "14e4:$wifi_id"
  grep -Fq $'systemctl\tenable\tomarchy-brcmfmac-suspend.service' "$calls" ||
    fail "Apple setup enables the sleep service" "$(cat "$calls")"
done
pass "Apple BCM4350/BCM43602 setup installs and enables the sleep service"

run_leaf "Apple Inc." 4464 >/dev/null
[[ ! -e $target ]] || fail "T2-era Apple Broadcom radios are left alone"
[[ ! -s $calls ]] || fail "T2-era Apple Broadcom radios change no system state" "$(cat "$calls")"
pass "T2-era Apple Broadcom radios are left alone"

run_leaf "LENOVO" 43ba >/dev/null
[[ ! -e $target ]] || fail "non-Apple BCM43602 hardware is left alone"
[[ ! -s $calls ]] || fail "non-Apple BCM43602 hardware changes no system state" "$(cat "$calls")"
pass "non-Apple BCM43602 hardware is left alone"

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
run_migration "Apple Inc." 43ba
cmp -s "$service" "$target" ||
  fail "the migration installs the service on an existing Apple BCM43602 system"
[[ -e $enabled ]] || fail "the migration enables the Broadcom sleep service"
pass "the migration repairs an existing Apple BCM43602 system"

run_migration "Apple Inc." 43ba
[[ ! -s $calls ]] || fail "the migration is idempotent" "$(cat "$calls")"
pass "the migration leaves a repaired system untouched"

rm -rf "$test_tmp/etc"
rm -f "$enabled"
run_migration "Apple Inc." 4464
[[ ! -e $target ]] || fail "the migration skips T2-era Apple Broadcom radios"
[[ ! -s $calls ]] || fail "the migration escalates nothing on unaffected hardware" "$(cat "$calls")"
pass "the migration skips unaffected hardware"
