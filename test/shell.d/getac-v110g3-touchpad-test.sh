#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

detector="$ROOT/bin/omarchy-hw-getac-v110g3"
leaf="$ROOT/install/hardware/getac/fix-v110g3-touchpad.sh"
all="$ROOT/install/hardware/all.sh"
migration=$(grep -l "getac/fix-v110g3-touchpad" "$ROOT"/migrations/*.sh | head -1)

grep -q 'run_logged .*hardware/getac/fix-v110g3-touchpad.sh' "$all" ||
  fail "the GETAC V110G3 touchpad quirk runs during hardware setup"
pass "the GETAC V110G3 touchpad quirk runs during hardware setup"

[[ -n $migration ]] || fail "a migration enables the quirk on existing installs"
pass "a migration enables the quirk on existing installs"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"
: >"$calls"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
exec "$@"
SH

cat >"$stub_bin/limine-mkinitcpio" <<'SH'
#!/bin/bash

echo 'limine-mkinitcpio' >>"$TEST_LOG"
SH

cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash

(( ${LIMINE_MKINITCPIO_INSTALLED:-1} == 1 ))
SH

cat >"$stub_bin/omarchy-state" <<'SH'
#!/bin/bash

printf 'state %s\n' "$*" >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

vendor_file="$test_tmp/sys_vendor"
product_file="$test_tmp/product_name"
drop_in="$test_tmp/getac-v110g3-touchpad.conf"
rebuild_marker="$test_tmp/rebuild-complete"

write_dmi() {
  printf '%s\n' "${1-GETAC}" >"$vendor_file"
  printf '%s\n' "${2-V110G3}" >"$product_file"
}

run_detector() {
  write_dmi "$@"
  OMARCHY_DMI_SYS_VENDOR="$vendor_file" \
    OMARCHY_DMI_PRODUCT_NAME="$product_file" \
    bash "$detector"
}

run_detector || fail "the detector matches GETAC V110G3"
pass "the detector matches GETAC V110G3"

run_detector "GETAC" "V110G4" && fail "the detector rejects another GETAC model"
pass "the detector rejects another GETAC model"

run_detector "Dell" "V110G3" && fail "the detector rejects another vendor"
pass "the detector rejects another vendor"

run_detector "Getac" "V110G3" || fail "the detector matches GETAC case-insensitively"
pass "the detector matches GETAC case-insensitively"

write_dmi "GETAC" "V110G3"
OMARCHY_DMI_SYS_VENDOR="$test_tmp/absent" \
  OMARCHY_DMI_PRODUCT_NAME="$product_file" \
  bash "$detector" && fail "the detector fails closed when the vendor attribute is missing"
pass "the detector fails closed when the vendor attribute is missing"

OMARCHY_DMI_SYS_VENDOR="$vendor_file" \
  OMARCHY_DMI_PRODUCT_NAME="$test_tmp/absent" \
  bash "$detector" && fail "the detector fails closed when the product attribute is missing"
pass "the detector fails closed when the product attribute is missing"

run_leaf() {
  : >"$calls"
  rm -f "$drop_in"
  write_dmi "${1-GETAC}" "${2-V110G3}"
  PATH="$stub_bin:$ROOT/bin:$PATH" \
    TEST_LOG="$calls" \
    OMARCHY_DMI_SYS_VENDOR="$vendor_file" \
    OMARCHY_DMI_PRODUCT_NAME="$product_file" \
    OMARCHY_GETAC_V110G3_LIMINE_CONF="$drop_in" \
    bash -c 'source "$1"' bash "$leaf"
}

run_leaf || fail "the leaf writes the Limine drop-in on the target machine"
grep -Fq 'KERNEL_CMDLINE[default]+=" i8042.nomux=1 psmouse.synaptics_intertouch=1"' "$drop_in" ||
  fail "the leaf writes the Limine drop-in on the target machine"
pass "the leaf writes the Limine drop-in on the target machine"

run_leaf "Dell" "XPS 13" || fail "the leaf no-ops on other hardware"
[[ -e $drop_in ]] && fail "the leaf no-ops on other hardware"
pass "the leaf no-ops on other hardware"

run_leaf || fail "the leaf is idempotent when the drop-in is already complete"
: >"$calls"
PATH="$stub_bin:$ROOT/bin:$PATH" \
  TEST_LOG="$calls" \
  OMARCHY_DMI_SYS_VENDOR="$vendor_file" \
  OMARCHY_DMI_PRODUCT_NAME="$product_file" \
  OMARCHY_GETAC_V110G3_LIMINE_CONF="$drop_in" \
  bash -c 'source "$1"' bash "$leaf"
[[ ! -s $calls ]] || fail "the leaf leaves a complete drop-in alone" "$(cat "$calls")"
pass "the leaf leaves a complete drop-in alone"

run_migration() {
  : >"$calls"
  write_dmi "${1-GETAC}" "${2-V110G3}"
  PATH="$stub_bin:$ROOT/bin:$PATH" \
    TEST_LOG="$calls" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_DMI_SYS_VENDOR="$vendor_file" \
    OMARCHY_DMI_PRODUCT_NAME="$product_file" \
    OMARCHY_GETAC_V110G3_LIMINE_CONF="$drop_in" \
    OMARCHY_GETAC_V110G3_REBUILD_MARKER="$rebuild_marker" \
    LIMINE_MKINITCPIO_INSTALLED="${3-1}" \
    bash -euo pipefail "$migration" >/dev/null
}

rm -f "$drop_in" "$rebuild_marker"
run_migration || fail "the migration writes the drop-in, rebuilds, and asks for a reboot"
grep -Fq 'KERNEL_CMDLINE[default]+=" i8042.nomux=1 psmouse.synaptics_intertouch=1"' "$drop_in" ||
  fail "the migration writes the Limine drop-in"
grep -Fxq 'limine-mkinitcpio' "$calls" || fail "the migration rebuilds the boot image"
grep -q 'state set reboot-required' "$calls" || fail "the migration asks for a reboot"
[[ -f $rebuild_marker ]] || fail "the migration records the machine-wide repair"
pass "the migration writes the drop-in, rebuilds, and asks for a reboot"

: >"$calls"
run_migration || fail "a recorded rebuild is not repeated"
[[ ! -s $calls ]] || fail "a recorded rebuild is not repeated" "$(cat "$calls")"
pass "the migration is machine-idempotent across users"

rm -f "$rebuild_marker"
: >"$calls"
run_migration || fail "an interrupted rebuild is retried"
grep -Fxq 'limine-mkinitcpio' "$calls" || fail "an interrupted rebuild is retried"
! grep -Eq $'sudo\ttee\t' "$calls" || fail "rebuild retry leaves a complete drop-in alone" "$(cat "$calls")"
pass "the migration retries an interrupted boot image rebuild"

rm -f "$drop_in" "$rebuild_marker"
run_migration "ThinkPad" "X1" || fail "the migration no-ops on other hardware"
[[ -e $drop_in ]] && fail "the migration no-ops on other hardware"
[[ -e $rebuild_marker ]] && fail "an untouched machine is not marked as repaired"
[[ ! -s $calls ]] || fail "the migration no-ops on other hardware" "$(cat "$calls")"
pass "the migration no-ops on other hardware"

rm -f "$drop_in" "$rebuild_marker"
: >"$calls"
run_migration "GETAC" "V110G3" 0 || fail "installs without limine-mkinitcpio still write the drop-in"
grep -Fq 'i8042.nomux=1' "$drop_in" || fail "installs without limine-mkinitcpio still write the drop-in"
grep -Fxq 'limine-mkinitcpio' "$calls" && fail "installs without limine-mkinitcpio skip the rebuild"
[[ -e $rebuild_marker ]] && fail "installs without limine-mkinitcpio are not marked as repaired"
pass "the migration skips the rebuild when limine-mkinitcpio is missing"
