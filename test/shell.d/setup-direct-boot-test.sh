#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

stub_bin="$test_dir/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/gum" <<'STUB'
#!/bin/bash
case "$1" in
  choose)
    if [[ -n ${STUB_GUM_CHOOSE:-} ]]; then
      echo "$STUB_GUM_CHOOSE"
      exit 0
    fi
    shift
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --header*|--selected*)
          shift 2 2>/dev/null || shift 1
          ;;
        --*)
          shift
          ;;
        *)
          echo "$1"
          exit 0
          ;;
      esac
    done
    head -n 1
    ;;
  confirm)
    [[ ${STUB_GUM_CONFIRM:-1} == 1 ]]
    ;;
  *)
    exit 0
    ;;
esac
STUB

cat >"$stub_bin/efibootmgr" <<'STUB'
#!/bin/bash
printf 'efibootmgr %s\n' "$*" >>"${CALL_LOG:?}"
if [[ -n ${STUB_EFIBOOTMGR_ENTRIES:-} ]]; then
  printf '%s\n' "$STUB_EFIBOOTMGR_ENTRIES"
else
  printf 'BootCurrent: 0000\nBootOrder: 0000\nBoot0000* EFI Hard Drive\n'
fi
STUB

cat >"$stub_bin/findmnt" <<'STUB'
#!/bin/bash
echo "/dev/nvme0n1p1"
STUB

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"${CALL_LOG:?}"
case "$1" in
  find)
    shift
    if [[ -d "${FAKE_BOOT_DIR:-}" ]]; then
      /usr/bin/find "$FAKE_BOOT_DIR" "${@:2}"
    else
      exit 0
    fi
    ;;
  efibootmgr)
    shift
    efibootmgr "$@"
    ;;
  *)
    exec "$@"
    ;;
esac
STUB

chmod +x "$stub_bin"/*

fake_boot="$test_dir/boot/EFI/Linux"
mkdir -p "$fake_boot"

run_direct_boot() {
  local scenario="$1"
  : >"$test_dir/$scenario.calls"

  CALL_LOG="$test_dir/$scenario.calls" \
    FAKE_BOOT_DIR="$fake_boot" \
    TEST_DIR="$test_dir" \
    STUB_GUM_CHOOSE="${STUB_GUM_CHOOSE:-}" \
    STUB_GUM_CONFIRM="${STUB_GUM_CONFIRM:-1}" \
    STUB_EFIBOOTMGR_ENTRIES="${STUB_EFIBOOTMGR_ENTRIES:-}" \
    PATH="$stub_bin:$PATH" \
    bash "$ROOT/bin/omarchy-setup-direct-boot"
}

# Test 1: Error when no UKIs found
if run_direct_boot no_uki >"$test_dir/no_uki.out" 2>&1; then
  fail "direct boot setup must fail when no UKI files are found"
fi
grep -q "No Omarchy UKI found" "$test_dir/no_uki.out" || fail "reports missing UKI error"
pass "direct boot setup errors when no UKIs exist"

# Test 2: Single kernel UKI auto-selected and created
touch "$fake_boot/omarchy_linux.efi"
output=$(run_direct_boot single_kernel)
grep -q "Creating EFI boot entry for omarchy_linux.efi" <<<"$output" || fail "creates EFI boot entry for single kernel"
grep -q "efibootmgr --create --disk /dev/nvme0n1 --part 1 --label Omarchy --loader \\\\EFI\\\\Linux\\\\omarchy_linux.efi" "$test_dir/single_kernel.calls" || fail "calls efibootmgr create correctly"
pass "direct boot setup configures entry for single kernel"

# Test 3: Multiple kernels available, user selects cachyos kernel
touch "$fake_boot/omarchy_linux-cachyos-bore.efi"
touch "$fake_boot/omarchy_linux-lts.efi"

STUB_GUM_CHOOSE="linux-cachyos-bore (omarchy_linux-cachyos-bore.efi)" output=$(run_direct_boot multi_kernel)
grep -q "Creating EFI boot entry for omarchy_linux-cachyos-bore.efi" <<<"$output" || fail "creates EFI boot entry for chosen cachyos kernel"
grep -q "efibootmgr --create --disk /dev/nvme0n1 --part 1 --label Omarchy --loader \\\\EFI\\\\Linux\\\\omarchy_linux-cachyos-bore.efi" "$test_dir/multi_kernel.calls" || fail "calls efibootmgr create with selected kernel UKI"
pass "direct boot setup allows choosing specific kernel among multiple installed kernels"

# Test 4: Existing entry - Disable direct boot
STUB_EFIBOOTMGR_ENTRIES="Boot0005* Omarchy HD(1,GPT,...)" STUB_GUM_CHOOSE="Disable direct boot" output=$(run_direct_boot disable_existing)
grep -q "Removing EFI boot entry 0005" <<<"$output" || fail "removes EFI boot entry when disabling"
grep -q "efibootmgr --bootnum 0005 --delete-bootnum" "$test_dir/disable_existing.calls" || fail "calls efibootmgr delete-bootnum"
pass "direct boot setup disables existing direct boot entry"

# Test 5: Existing entry - Change kernel
cat >"$stub_bin/gum" <<'STUB'
#!/bin/bash
case "$1" in
  choose)
    state_file="${TEST_DIR:-/tmp}/gum_choose_state"
    if [[ ! -f $state_file ]]; then
      echo 1 >"$state_file"
      echo "Change kernel"
    else
      echo "linux-lts (omarchy_linux-lts.efi)"
    fi
    ;;
  confirm)
    [[ ${STUB_GUM_CONFIRM:-1} == 1 ]]
    ;;
  *)
    exit 0
    ;;
esac
STUB
chmod +x "$stub_bin/gum"

STUB_EFIBOOTMGR_ENTRIES="Boot0005* Omarchy HD(1,GPT,...)" output=$(run_direct_boot change_kernel)
grep -q "Removing existing EFI boot entry 0005" <<<"$output" || fail "removes old entry when changing kernel"
grep -q "Creating EFI boot entry for omarchy_linux-lts.efi" <<<"$output" || fail "creates new entry for changed kernel"
grep -q "efibootmgr --bootnum 0005 --delete-bootnum" "$test_dir/change_kernel.calls" || fail "deletes old bootnum"
grep -q "efibootmgr --create --disk /dev/nvme0n1 --part 1 --label Omarchy --loader \\\\EFI\\\\Linux\\\\omarchy_linux-lts.efi" "$test_dir/change_kernel.calls" || fail "creates new entry"
pass "direct boot setup supports changing kernel on existing direct boot configuration"
