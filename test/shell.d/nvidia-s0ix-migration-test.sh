#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1787818004.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"
: >"$calls"

cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash

(( ${LIMINE_MKINITCPIO_INSTALLED:-1} == 1 ))
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
(( ${LIMINE_MKINITCPIO_FAILS:-0} == 0 ))
SH

cat >"$stub_bin/omarchy-state" <<'SH'
#!/bin/bash

printf 'omarchy-state' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

conf="$test_tmp/nvidia-s0ix.conf"
marker="$test_tmp/s0ix-marker"
mem_sleep="$test_tmp/mem_sleep"

# Each argument is a PCI device as "vendor:class", in sysfs's own format.
write_pci_devices() {
  rm -rf "$test_tmp/devices"
  mkdir -p "$test_tmp/devices"

  local index=0
  local spec
  for spec in "$@"; do
    local slot
    slot=$(printf '0000:%02x:00.0' "$index")
    mkdir -p "$test_tmp/devices/$slot"
    printf '%s\n' "${spec%%:*}" >"$test_tmp/devices/$slot/vendor"
    printf '%s\n' "${spec##*:}" >"$test_tmp/devices/$slot/class"
    index=$((index + 1))
  done
}

run_migration() {
  PATH="$stub_bin:$ROOT/bin:$PATH" \
    TEST_LOG="$calls" \
    OMARCHY_MEM_SLEEP="$mem_sleep" \
    OMARCHY_NVIDIA_S0IX_CONF="$conf" \
    OMARCHY_NVIDIA_S0IX_MARKER="$marker" \
    OMARCHY_PCI_DEVICES_PATH="$test_tmp/devices" \
    bash -euo pipefail "$migration" >/dev/null
}

# NVIDIA machine sleeping via s2idle: the option is written, the initramfs
# rebuilt, the machine-wide repair recorded, and a reboot requested.
write_pci_devices 0x10de:0x030000
echo '[s2idle] deep' >"$mem_sleep"
run_migration

grep -Fxq 'options nvidia NVreg_EnableS0ixPowerManagement=1' "$conf" ||
  fail "the S0ix option is written to the modprobe conf"
grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "the initramfs is rebuilt so the early-loaded module sees the option"
[[ -f $marker ]] || fail "the rebuild records the machine-wide repair"
grep -Pq 'omarchy-state\tset\treboot-required' "$calls" ||
  fail "the migration requests a reboot"
pass "migration enables S0ix on an s2idle NVIDIA machine"

: >"$calls"
run_migration

[[ ! -s $calls ]] || fail "a recorded repair is not repeated" "$(cat "$calls")"
pass "migration is machine-idempotent across users"

# A failed rebuild must abort before the marker lands, so the migration stays
# pending and the next run retries the rebuild.
rm -f "$conf" "$marker"
: >"$calls"
if LIMINE_MKINITCPIO_FAILS=1 run_migration 2>/dev/null; then
  fail "a failed initramfs rebuild aborts the migration"
fi

[[ -f $conf ]] || fail "the conf from the interrupted run is kept for the retry"
[[ ! -e $marker ]] || fail "a failed rebuild is not recorded as complete"

: >"$calls"
run_migration

grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "an interrupted rebuild is retried"
[[ -f $marker ]] || fail "the retried rebuild records the repair"
pass "migration retries a failed initramfs rebuild"

# Machines sleeping via deep S3: the option is meaningless there, and one
# #5274 reporter reproduces a distinct freeze under S3, so leave them alone.
rm -f "$conf" "$marker"
echo 's2idle [deep]' >"$mem_sleep"
: >"$calls"
run_migration

[[ ! -s $calls && ! -e $conf ]] || fail "a deep-sleep machine is left alone" "$(cat "$calls")"
pass "migration skips machines sleeping via deep S3"

echo '[s2idle] deep' >"$mem_sleep"
write_pci_devices 0x1002:0x030000
run_migration

[[ ! -s $calls && ! -e $conf ]] || fail "machines without an NVIDIA GPU are skipped" "$(cat "$calls")"

write_pci_devices 0x10de:0x030000
LIMINE_MKINITCPIO_INSTALLED=0 run_migration

[[ ! -s $calls && ! -e $conf ]] || fail "installs without limine-mkinitcpio are skipped" "$(cat "$calls")"
pass "migration skips installs it does not apply to"
