#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/intel/ptl-kernel.sh"
migration="$ROOT/migrations/1786961462.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
boot_order_conf="$test_tmp/zz-panther-lake-kernel.conf"
old_boot_order_conf="$test_tmp/dell-xps-panther-lake.conf"
legacy_boot_order_conf="$test_tmp/zz-dell-xps-panther-lake.conf"
mkdir -p "$stub_bin"
: >"$calls"

cat >"$stub_bin/omarchy-hw-match" <<'SH'
#!/bin/bash

[[ $1 == "XPS" ]] && (( ${XPS_MATCH:-0} == 1 ))
SH

cat >"$stub_bin/omarchy-hw-intel-ptl" <<'SH'
#!/bin/bash

(( ${PTL_MATCH:-0} == 1 ))
SH

cat >"$stub_bin/omarchy-hw-asus-expertbook-b9406" <<'SH'
#!/bin/bash

(( ${B9406_MATCH:-0} == 1 ))
SH

cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash

printf 'omarchy-pkg-add' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash

printf 'pacman' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"

if [[ $1 == "-Qq" && $2 == "linux" ]]; then
  exit 1
fi
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

cat >"$stub_bin/omarchy-state" <<'SH'
#!/bin/bash

printf 'omarchy-state' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

run_leaf() {
  local xps="$1" ptl="$2" b9406="$3"
  : >"$calls"
  rm -f "$boot_order_conf"
  touch "$legacy_boot_order_conf"

  XPS_MATCH="$xps" PTL_MATCH="$ptl" B9406_MATCH="$b9406" \
    TEST_LOG="$calls" PATH="$stub_bin:$PATH" OMARCHY_TESTING=1 \
    OMARCHY_PTL_BOOT_ORDER_CONF="$boot_order_conf" \
    OMARCHY_PTL_OLD_BOOT_ORDER_CONF="$old_boot_order_conf" \
    OMARCHY_PTL_LEGACY_BOOT_ORDER_CONF="$legacy_boot_order_conf" \
    bash -euo pipefail "$leaf" >/dev/null
}

run_leaf 0 1 1
grep -Fxq $'omarchy-pkg-add\tlinux-ptl\tlinux-ptl-headers' "$calls" ||
  fail "the B9406 installs the patched kernel" "$(cat "$calls")"
grep -Fxq $'pacman\t-Rdd\t--noconfirm\tlinux\tlinux-headers' "$calls" ||
  fail "the B9406 removes the superseded stock kernel" "$(cat "$calls")"
grep -Fq 'BOOT_ORDER="linux-ptl*, *fallback, Snapshots"' "$boot_order_conf" ||
  fail "the B9406 boots the patched kernel by default"
[[ ! -e $legacy_boot_order_conf ]] || fail "the legacy Dell boot-order drop-in is removed"
pass "the B9406 selects the audio-capable Panther Lake kernel"

run_leaf 1 1 0
grep -Fxq $'omarchy-pkg-add\tlinux-ptl\tlinux-ptl-headers' "$calls" ||
  fail "a Panther Lake XPS keeps the patched kernel" "$(cat "$calls")"
pass "the existing Dell XPS kernel path is preserved"

run_leaf 1 0 0
[[ ! -s $calls ]] || fail "a non-Panther-Lake XPS is left alone" "$(cat "$calls")"
[[ ! -e $boot_order_conf ]] || fail "a non-Panther-Lake XPS gets no boot override"

run_leaf 0 1 0
[[ ! -s $calls ]] || fail "an unrelated Panther Lake system is left alone" "$(cat "$calls")"
[[ ! -e $boot_order_conf ]] || fail "an unrelated Panther Lake system gets no boot override"
pass "unrelated hardware does not install the custom kernel"

: >"$calls"
rm -f "$boot_order_conf"

B9406_MATCH=1 XPS_MATCH=0 PTL_MATCH=1 TEST_LOG="$calls" \
  PATH="$stub_bin:$PATH" OMARCHY_PATH="$ROOT" OMARCHY_TESTING=1 \
  OMARCHY_PTL_BOOT_ORDER_CONF="$boot_order_conf" \
  OMARCHY_PTL_OLD_BOOT_ORDER_CONF="$old_boot_order_conf" \
  OMARCHY_PTL_LEGACY_BOOT_ORDER_CONF="$legacy_boot_order_conf" \
  bash -euo pipefail "$migration" >/dev/null

grep -Fxq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "the B9406 migration requests the reboot needed for the new kernel" "$(cat "$calls")"
grep -Fq 'BOOT_ORDER="linux-ptl*, *fallback, Snapshots"' "$boot_order_conf" ||
  fail "the B9406 migration installs the kernel boot override"
pass "existing B9406 installs receive the patched kernel"

: >"$calls"
rm -f "$boot_order_conf"

B9406_MATCH=0 XPS_MATCH=0 PTL_MATCH=1 TEST_LOG="$calls" \
  PATH="$stub_bin:$PATH" OMARCHY_PATH="$ROOT" OMARCHY_TESTING=1 \
  OMARCHY_PTL_BOOT_ORDER_CONF="$boot_order_conf" \
  OMARCHY_PTL_OLD_BOOT_ORDER_CONF="$old_boot_order_conf" \
  OMARCHY_PTL_LEGACY_BOOT_ORDER_CONF="$legacy_boot_order_conf" \
  bash -euo pipefail "$migration" >/dev/null

[[ ! -s $calls ]] || fail "the B9406 migration skips unrelated hardware" "$(cat "$calls")"
[[ ! -e $boot_order_conf ]] || fail "the migration adds no unrelated boot override"
pass "the B9406 migration is hardware-scoped"
