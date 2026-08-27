#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

detector="$ROOT/bin/omarchy-hw-dell-xps13-sidecar-amps"
leaf="$ROOT/install/hardware/dell-xps13-sidecar-amps.sh"
all="$ROOT/install/hardware/all.sh"
migration=$(grep -l "dell-xps13-sidecar-amps" "$ROOT"/migrations/*.sh | head -1)

grep -q 'run_logged .*hardware/dell-xps13-sidecar-amps.sh' "$all" ||
  fail "the sidecar amplifier workaround runs during hardware setup"
pass "the sidecar amplifier workaround runs during hardware setup"

# The apply step rebuilds the boot image, so it has to see the Panther Lake
# kernel that ptl-kernel.sh swaps in rather than the stock one it replaces.
ptl_line=$(grep -n 'hardware/intel/ptl-kernel.sh' "$all" | cut -d: -f1)
amps_line=$(grep -n 'hardware/dell-xps13-sidecar-amps.sh' "$all" | cut -d: -f1)
((ptl_line < amps_line)) ||
  fail "the sidecar amplifier workaround runs after the Panther Lake kernel swap"
pass "the sidecar amplifier workaround runs after the Panther Lake kernel swap"

[[ -n $migration ]] || fail "a migration enables the workaround on existing installs"
pass "a migration enables the workaround on existing installs"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"

cat >"$test_tmp/bin/omarchy-hw-match" <<'SH'
#!/bin/bash
[[ ${TEST_PRODUCT_NAME:-} == *"$1"* ]]
SH

cat >"$test_tmp/bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'pkg-add %s\n' "$*" >>"$CALL_LOG"
exit "${TEST_PKG_ADD_STATUS:-0}"
SH

cat >"$test_tmp/bin/sudo" <<'SH'
#!/bin/bash
exec "$@"
SH

cat >"$test_tmp/bin/dell-xps13-sidecar-amps-apply" <<'SH'
#!/bin/bash
printf 'apply\n' >>"$CALL_LOG"
exit "${TEST_APPLY_STATUS:-0}"
SH

cat >"$test_tmp/bin/omarchy-state" <<'SH'
#!/bin/bash
printf 'state %s\n' "$*" >>"$CALL_LOG"
SH

chmod +x "$test_tmp/bin"/*

sku_file="$test_tmp/product_sku"
call_log="$test_tmp/calls.log"

run_detector() {
  printf '%s\n' "${2-0E53}" >"$sku_file"
  PATH="$test_tmp/bin:$PATH" \
    TEST_PRODUCT_NAME="${1-XPS 13 DX13260}" \
    OMARCHY_DMI_PRODUCT_SKU="${3-$sku_file}" \
    bash "$detector"
}

run_detector || fail "the detector matches the DX13260 with SKU 0E53"
pass "the detector matches the DX13260 with SKU 0E53"

run_detector "XPS 13 DX13261" && fail "the detector rejects another model"
pass "the detector rejects another model"

run_detector "XPS 13 DX13260" "0E54" && fail "the detector rejects another SKU"
pass "the detector rejects another SKU"

# An exact match must not be satisfied by a SKU that merely contains it.
run_detector "XPS 13 DX13260" "0E530" && fail "the detector rejects a longer SKU"
pass "the detector rejects a longer SKU"

run_detector "XPS 13 DX13260" "0E53" "$test_tmp/absent" &&
  fail "the detector fails closed when the SKU attribute is missing"
pass "the detector fails closed when the SKU attribute is missing"

# Sourced the way run_logged runs it.
run_leaf() {
  : >"$call_log"
  printf '0E53\n' >"$sku_file"
  PATH="$test_tmp/bin:$ROOT/bin:$PATH" \
    CALL_LOG="$call_log" \
    TEST_PRODUCT_NAME="${1-XPS 13 DX13260}" \
    TEST_PKG_ADD_STATUS="${2:-0}" \
    TEST_APPLY_STATUS="${3:-0}" \
    OMARCHY_DMI_PRODUCT_SKU="$sku_file" \
    bash -c 'source "$1"' bash "$leaf"
}

run_leaf || fail "the leaf installs and applies on the target machine"
grep -q 'pkg-add dell-xps13-sidecar-amps' "$call_log" ||
  fail "the leaf installs the package on the target machine"
grep -q '^apply$' "$call_log" ||
  fail "the leaf applies the workaround on the target machine"
pass "the leaf installs and applies on the target machine"

run_leaf "ThinkPad X1" || fail "the leaf no-ops on other hardware"
[[ -s $call_log ]] && fail "the leaf no-ops on other hardware"
pass "the leaf no-ops on other hardware"

# Pacman registers a package even when its scriptlet fails, so a failing apply
# has to surface rather than be swallowed by a successful install.
run_leaf "XPS 13 DX13260" 0 1 && fail "a failing apply fails the leaf"
pass "a failing apply fails the leaf"

run_leaf "XPS 13 DX13260" 1 && fail "a failing package install fails the leaf"
grep -q '^apply$' "$call_log" && fail "a failing package install skips the apply"
pass "a failing package install fails the leaf without applying"

# The migration runner uses bash -euo pipefail and only records the migration
# when it exits clean, so a failed apply has to leave reboot-required unset.
run_migration() {
  : >"$call_log"
  printf '0E53\n' >"$sku_file"
  PATH="$test_tmp/bin:$ROOT/bin:$PATH" \
    CALL_LOG="$call_log" \
    OMARCHY_PATH="$ROOT" \
    TEST_PRODUCT_NAME="${1-XPS 13 DX13260}" \
    TEST_APPLY_STATUS="${2:-0}" \
    OMARCHY_DMI_PRODUCT_SKU="$sku_file" \
    bash -euo pipefail "$migration" >/dev/null
}

run_migration || fail "the migration applies the workaround and asks for a reboot"
grep -q 'state set reboot-required' "$call_log" ||
  fail "the migration applies the workaround and asks for a reboot"
pass "the migration applies the workaround and asks for a reboot"

run_migration "XPS 13 DX13260" 1 && fail "a failing apply leaves the migration pending"
grep -q 'state set reboot-required' "$call_log" &&
  fail "a failing apply does not mark reboot-required"
pass "a failing apply leaves the migration pending without marking reboot-required"

run_migration "ThinkPad X1" || fail "the migration no-ops on other hardware"
[[ -s $call_log ]] && fail "the migration no-ops on other hardware"
pass "the migration no-ops on other hardware"
