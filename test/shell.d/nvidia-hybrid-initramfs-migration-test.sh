#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1787683023.sh"

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

"$@"
SH

cat >"$stub_bin/limine-mkinitcpio" <<'SH'
#!/bin/bash

echo 'limine-mkinitcpio' >>"$TEST_LOG"
exit "${LIMINE_MKINITCPIO_STATUS:-0}"
SH

chmod +x "$stub_bin"/*

nvidia_conf="$test_tmp/nvidia.conf"
rebuild_marker="$test_tmp/rebuild-complete"
nvidia_conf_body='MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)'

write_nvidia_conf() {
  echo "$nvidia_conf_body" >"$nvidia_conf"
}

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

# The migration shells out to omarchy-hw-nvidia-only-display, so the real
# helper from bin/ sits on PATH behind the stubs.
run_migration() {
  PATH="$stub_bin:$ROOT/bin:$PATH" \
    TEST_LOG="$calls" \
    OMARCHY_MKINITCPIO_NVIDIA_CONF="$nvidia_conf" \
    OMARCHY_NVIDIA_REBUILD_MARKER="$rebuild_marker" \
    OMARCHY_PCI_DEVICES_PATH="$test_tmp/devices" \
    bash -euo pipefail "$migration" >/dev/null 2>&1
}

# Hybrid laptop (Intel iGPU + NVIDIA dGPU): the drop-in goes, the image is
# rebuilt, and the repair is recorded.
write_pci_devices 0x8086:0x030000 0x10de:0x030200
write_nvidia_conf
run_migration

[[ ! -e $nvidia_conf ]] || fail "a hybrid machine loses the nvidia drop-in"
grep -Fxq 'limine-mkinitcpio' "$calls" || fail "a hybrid machine rebuilds its initramfs"
[[ -f $rebuild_marker ]] || fail "the rebuild records the machine-wide repair"
pass "migration removes the drop-in and rebuilds on a hybrid machine"

: >"$calls"
run_migration

[[ ! -s $calls ]] || fail "a recorded rebuild is not repeated" "$(cat "$calls")"
pass "migration is machine-idempotent across users"

# A rebuild that fails must leave the machine retryable: the drop-in comes
# back, nothing is marked done, and the next run rebuilds again.
rm -f "$rebuild_marker"
write_nvidia_conf
: >"$calls"
if LIMINE_MKINITCPIO_STATUS=1 run_migration; then
  fail "a failed rebuild is reported as a failure"
fi

[[ -f $nvidia_conf ]] || fail "a failed rebuild restores the nvidia drop-in"
[[ $(<"$nvidia_conf") == "$nvidia_conf_body" ]] || fail "the restored drop-in is intact"
[[ ! -e $rebuild_marker ]] || fail "a failed rebuild is not marked as repaired"
pass "migration restores the drop-in when the rebuild fails"

: >"$calls"
run_migration

grep -Fxq 'limine-mkinitcpio' "$calls" || fail "a failed rebuild is retried on the next run"
[[ ! -e $nvidia_conf ]] || fail "the retry removes the drop-in again"
[[ -f $rebuild_marker ]] || fail "the retry records the repair"
pass "migration retries after a failed rebuild"

# NVIDIA-only desktop: the early load is what gives it KMS at the LUKS prompt.
write_pci_devices 0x10de:0x030000
rm -f "$rebuild_marker"
write_nvidia_conf
: >"$calls"
run_migration

[[ -f $nvidia_conf ]] || fail "an NVIDIA-only machine keeps its drop-in"
[[ ! -s $calls ]] || fail "an NVIDIA-only machine is left alone" "$(cat "$calls")"
[[ ! -e $rebuild_marker ]] || fail "an untouched machine is not marked as repaired"
pass "migration skips an NVIDIA-only machine"

# Installs the migration does not apply to.
write_pci_devices 0x8086:0x030000 0x10de:0x030200
: >"$calls"
LIMINE_MKINITCPIO_INSTALLED=0 run_migration

[[ ! -s $calls ]] || fail "installs without limine-mkinitcpio are skipped" "$(cat "$calls")"

rm -f "$nvidia_conf"
run_migration

[[ ! -s $calls ]] || fail "machines without the nvidia drop-in are skipped" "$(cat "$calls")"
[[ ! -e $rebuild_marker ]] || fail "a skipped machine is not marked as repaired"
pass "migration skips installs it does not apply to"
