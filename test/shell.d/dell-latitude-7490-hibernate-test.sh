#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/intel/fix-dell-latitude-7490-hibernate.sh"
all="$ROOT/install/hardware/all.sh"
migration=$(grep -l "fix-dell-latitude-7490-hibernate" "$ROOT"/migrations/*.sh | head -1)

grep -q 'run_logged .*hardware/intel/fix-dell-latitude-7490-hibernate.sh' "$all" ||
  fail "the Latitude 7490 hibernation quirk runs during hardware setup"
pass "the Latitude 7490 hibernation quirk runs during hardware setup"

[[ -n $migration ]] || fail "a migration enables the quirk on existing installs"
pass "a migration enables the quirk on existing installs"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"

cat >"$test_tmp/bin/sudo" <<'SH'
#!/bin/bash
exec "$@"
SH

cat >"$test_tmp/bin/limine-mkinitcpio" <<'SH'
#!/bin/bash
echo limine-mkinitcpio >>"$TEST_LOG"
exit "${TEST_LIMINE_STATUS:-0}"
SH

cat >"$test_tmp/bin/omarchy-state" <<'SH'
#!/bin/bash
printf 'omarchy-state %s\n' "$*" >>"$TEST_LOG"
SH

chmod +x "$test_tmp/bin"/*

vendor_file="$test_tmp/sys_vendor"
product_file="$test_tmp/product_name"
limine_conf="$test_tmp/dell-latitude-7490-i915.conf"
repair_marker="$test_tmp/latitude-7490-repair-complete"
call_log="$test_tmp/calls.log"

run_leaf() {
  : >"$call_log"
  printf '%s\n' "${1-Dell Inc.}" >"$vendor_file"
  printf '%s\n' "${2-Latitude 7490}" >"$product_file"

  PATH="$test_tmp/bin:$PATH" \
    TEST_LOG="$call_log" \
    OMARCHY_LATITUDE_7490_DMI_VENDOR="$vendor_file" \
    OMARCHY_LATITUDE_7490_DMI_PRODUCT="$product_file" \
    OMARCHY_LATITUDE_7490_LIMINE_CONF="$limine_conf" \
    OMARCHY_LATITUDE_7490_REPAIR_MARKER="$repair_marker" \
    TEST_LIMINE_STATUS="${3:-0}" \
    bash -euo pipefail -c 'source "$1"' bash "$leaf"
}

run_leaf || fail "the target Latitude gets the i915 display C-state quirk"
grep -Fxq 'KERNEL_CMDLINE[default]+=" i915.enable_dc=0"' "$limine_conf" ||
  fail "the target Latitude gets the i915 display C-state parameter"
grep -Fxq 'limine-mkinitcpio' "$call_log" ||
  fail "adding the quirk rebuilds the boot image"
[[ -f $repair_marker ]] || fail "a successful rebuild records completion"
pass "the target Latitude gets the i915 display C-state quirk"

run_leaf || fail "the Latitude quirk is idempotent"
[[ ! -s $call_log ]] || fail "an already configured Latitude is left unchanged"
pass "the Latitude quirk is idempotent"

rm -f "$repair_marker"
run_leaf "Dell Inc." "Latitude 7490" 1 &&
  fail "a failed rebuild fails the hardware setup"
[[ ! -e $repair_marker ]] || fail "a failed rebuild does not record completion"
pass "a failed rebuild remains pending"

run_leaf || fail "a pending rebuild is retried"
grep -Fxq 'limine-mkinitcpio' "$call_log" ||
  fail "a pending rebuild runs limine-mkinitcpio again"
[[ -f $repair_marker ]] || fail "a successful retry records completion"
pass "a failed rebuild is retried successfully"

run_leaf || fail "a completed rebuild remains idempotent"
[[ ! -s $call_log ]] || fail "a completed rebuild is not repeated"
pass "a completed rebuild remains idempotent"

rm -f "$limine_conf"
rm -f "$repair_marker"
run_leaf "Dell Inc." "Latitude 7480" || fail "another Dell model is handled safely"
[[ ! -e $limine_conf ]] || fail "another Dell model does not get the quirk"
[[ ! -s $call_log ]] || fail "another Dell model does not rebuild the boot image"
pass "another Dell model does not get the quirk"

run_leaf "LENOVO" "Latitude 7490" || fail "another vendor is handled safely"
[[ ! -e $limine_conf ]] || fail "another vendor does not get the quirk"
[[ ! -s $call_log ]] || fail "another vendor does not rebuild the boot image"
pass "another vendor does not get the quirk"

: >"$call_log"
printf '%s\n' 'Dell Inc.' >"$vendor_file"
printf '%s\n' 'Latitude 7490' >"$product_file"

PATH="$test_tmp/bin:$PATH" \
  TEST_LOG="$call_log" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_LATITUDE_7490_DMI_VENDOR="$vendor_file" \
  OMARCHY_LATITUDE_7490_DMI_PRODUCT="$product_file" \
  OMARCHY_LATITUDE_7490_LIMINE_CONF="$limine_conf" \
  OMARCHY_LATITUDE_7490_REPAIR_MARKER="$repair_marker" \
  bash -euo pipefail "$migration" >/dev/null

grep -Fxq 'omarchy-state set reboot-required' "$call_log" ||
  fail "the migration requests a reboot after enabling the quirk"
pass "the migration enables the quirk and requests a reboot"
