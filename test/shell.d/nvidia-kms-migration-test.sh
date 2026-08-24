#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1786605598.sh"
packaged_hooks="$ROOT/etc/mkinitcpio.conf.d/omarchy_hooks.conf"

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
SH

chmod +x "$stub_bin"/*

hooks_conf="$test_tmp/omarchy_hooks.conf"
nvidia_conf="$test_tmp/nvidia.conf"
rebuild_marker="$test_tmp/rebuild-complete"

cp "$packaged_hooks" "$hooks_conf"
echo 'MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)' >"$nvidia_conf"

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
  PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" \
    OMARCHY_MKINITCPIO_HOOKS_CONF="$hooks_conf" \
    OMARCHY_MKINITCPIO_NVIDIA_CONF="$nvidia_conf" \
    OMARCHY_KMS_REBUILD_MARKER="$rebuild_marker" \
    OMARCHY_PCI_DEVICES_PATH="$test_tmp/devices" \
    bash -euo pipefail "$migration" >/dev/null
}

# NVIDIA-only machine with the proprietary driver: the packaged conditional
# drops kms, so the stale initramfs must be rebuilt once.
write_pci_devices 0x10de:0x030000
run_migration

grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "an NVIDIA-only machine rebuilds its initramfs"
[[ -f $rebuild_marker ]] || fail "the rebuild records the machine-wide repair"
pass "migration rebuilds the initramfs on an NVIDIA-only machine"

: >"$calls"
run_migration

[[ ! -s $calls ]] || fail "a recorded rebuild is not repeated" "$(cat "$calls")"
pass "migration is machine-idempotent across users"

rm -f "$rebuild_marker"
: >"$calls"
run_migration

grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "an interrupted rebuild is retried"
pass "migration retries an interrupted rebuild"

# Hybrid machine: the conditional keeps kms, so the initramfs already matches.
write_pci_devices 0x1002:0x030000 0x10de:0x030200
rm -f "$rebuild_marker"
: >"$calls"
run_migration

[[ ! -s $calls ]] || fail "a hybrid machine is left alone" "$(cat "$calls")"
[[ ! -e $rebuild_marker ]] || fail "an untouched machine is not marked as repaired"
pass "migration skips a hybrid machine that keeps kms"

# A user-edited hooks conf predating the conditional (the packaged update sits
# in a .pacnew) still carries kms unconditionally: nothing to rebuild for.
write_pci_devices 0x10de:0x030000
echo 'HOOKS=(base udev autodetect modconf kms block filesystems fsck)' >"$hooks_conf"
: >"$calls"
run_migration

[[ ! -s $calls ]] || fail "a user-edited hooks conf is left alone" "$(cat "$calls")"
pass "migration skips a hooks conf without the conditional"

cp "$packaged_hooks" "$hooks_conf"

: >"$calls"
LIMINE_MKINITCPIO_INSTALLED=0 run_migration

[[ ! -s $calls ]] || fail "installs without limine-mkinitcpio are skipped" "$(cat "$calls")"

mv "$nvidia_conf" "$nvidia_conf.away"
run_migration
mv "$nvidia_conf.away" "$nvidia_conf"

[[ ! -s $calls ]] || fail "machines without the proprietary NVIDIA driver are skipped" "$(cat "$calls")"
pass "migration skips installs it does not apply to"
