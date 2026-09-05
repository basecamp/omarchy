#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Exercise the real script with fake firmware, kernels, and ESP, even on BIOS
# hosts. No test may read or write the host's EFI variables or boot partition.
if [[ ${DIRECT_BOOT_TEST_NAMESPACE:-} != 1 ]]; then
  if unshare --user --map-root-user --mount true 2>/dev/null; then
    exec env DIRECT_BOOT_TEST_NAMESPACE=1 unshare --user --map-root-user --mount --propagation private bash "$0" "$@"
  fi
  pass "user/mount namespaces unavailable; skipping direct boot setup tests"
  exit 0
fi

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
direct_boot_script=${1:-$ROOT/bin/omarchy-setup-direct-boot}

mkdir -p "$test_dir"/{bin,sys/firmware/efi,sys/class/dmi/id,boot/EFI/Linux,modules/test-kernel}
echo HP > "$test_dir/sys/class/dmi/id/bios_vendor"
mount --bind "$test_dir/sys" /sys
mount --bind "$test_dir/boot" /boot
mount --bind "$test_dir/modules" /usr/lib/modules

export CALL_LOG="$test_dir/calls"
export CONFIRM_LOG="$test_dir/confirm"
export PATH="$test_dir/bin:$PATH"

cat > "$test_dir/bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
cat > "$test_dir/bin/uname" <<'STUB'
#!/bin/bash
echo test-kernel
STUB
cat > "$test_dir/bin/findmnt" <<'STUB'
#!/bin/bash
echo /dev/nvme0n1p1
STUB
cat > "$test_dir/bin/find" <<'STUB'
#!/bin/bash
# Reproduce the ESP's stock-first enumeration regardless of the test filesystem.
/usr/bin/find "$@" | sort -r
STUB
cat > "$test_dir/bin/efibootmgr" <<'STUB'
#!/bin/bash
if (( $# == 0 )); then
  printf '%s\n' "${EFI_ENTRIES:-BootCurrent: 0000}"
else
  printf '%s\n' "$*" >> "$CALL_LOG"
fi
STUB
cat > "$test_dir/bin/gum" <<'STUB'
#!/bin/bash
[[ $1 == confirm ]] || exit 1
printf '%s\n' "$2" >> "$CONFIRM_LOG"
exit "${CONFIRM_STATUS:-0}"
STUB
chmod +x "$test_dir/bin/"*

run_setup() {
  : > "$CALL_LOG"
  : > "$CONFIRM_LOG"
  bash "$direct_boot_script" > "$test_dir/output" 2>&1
}

assert_loader() {
  local expected="--create --disk /dev/nvme0n1 --part 1 --label Omarchy --loader \\EFI\\Linux\\$1"
  [[ $(cat "$CALL_LOG") == "$expected" ]] || fail "direct boot uses $1" "$(cat "$CALL_LOG")"
}

# Both kernels are installed, as on the affected laptop.
touch /boot/EFI/Linux/omarchy_linux.efi
touch /boot/EFI/Linux/omarchy_linux-csc3554.efi
echo linux-csc3554 > /usr/lib/modules/test-kernel/pkgbase
run_setup
assert_loader omarchy_linux-csc3554.efi
grep -q 'with linux-csc3554' "$CONFIRM_LOG" || fail "confirmation identifies the selected kernel"
pass "direct boot retains the running custom kernel when stock linux is also installed"

echo linux > /usr/lib/modules/test-kernel/pkgbase
run_setup
assert_loader omarchy_linux.efi
pass "direct boot retains stock linux when it is the running kernel"

rm /boot/EFI/Linux/omarchy_linux.efi
echo linux-csc3554 > /usr/lib/modules/test-kernel/pkgbase
run_setup
assert_loader omarchy_linux-csc3554.efi
pass "direct boot supports a single custom kernel"

CONFIRM_STATUS=1 run_setup
[[ ! -s $CALL_LOG ]] || fail "declining confirmation must not change EFI entries"
pass "declining confirmation leaves EFI entries untouched"

touch /boot/EFI/Linux/omarchy_linux.efi
rm /boot/EFI/Linux/omarchy_linux-csc3554.efi
if run_setup; then
  fail "missing running-kernel UKI must fail"
fi
grep -q 'No Omarchy UKI found for the running kernel' "$test_dir/output" || fail "missing UKI is explained"
[[ ! -s $CALL_LOG && ! -s $CONFIRM_LOG ]] || fail "missing UKI must not select stock linux"
pass "missing custom UKI fails without falling back to stock linux"

rm /usr/lib/modules/test-kernel/pkgbase
if run_setup; then
  fail "missing running-kernel metadata must fail"
fi
grep -q 'Reboot into an installed kernel' "$test_dir/output" || fail "missing metadata explains how to recover"
[[ ! -s $CALL_LOG && ! -s $CONFIRM_LOG ]] || fail "missing metadata must not change EFI entries"
pass "removed running-kernel metadata fails without guessing another kernel"

EFI_ENTRIES='Boot0007* Omarchy HD(1,GPT,...)' run_setup
[[ $(cat "$CALL_LOG") == '--bootnum 0007 --delete-bootnum' ]] || fail "existing entry can still be disabled"
pass "disabling direct boot does not require running-kernel metadata"
