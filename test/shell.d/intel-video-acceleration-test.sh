#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/intel/video-acceleration.sh"
migration=$(grep -l 'intel-media-driver libva-intel-driver' "$ROOT"/migrations/*.sh | head -1)

[[ -n $migration ]] || fail "a migration brings existing installs onto both VA-API drivers"
pass "a migration brings existing installs onto both VA-API drivers"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"

cat >"$test_tmp/bin/lspci" <<'SH'
#!/bin/bash
printf '%s\n' "${TEST_LSPCI_LINE:-00:02.0 VGA compatible controller: Intel Corporation Ivy Bridge mobile GT2 [HD Graphics 4000] (rev 09)}"
SH

cat >"$test_tmp/bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'pkg-add %s\n' "$*" >>"$CALL_LOG"
SH

chmod +x "$test_tmp/bin"/*

call_log="$test_tmp/calls.log"

run_leaf() {
  : >"$call_log"
  PATH="$test_tmp/bin:$PATH" \
    CALL_LOG="$call_log" \
    TEST_LSPCI_LINE="${1-}" \
    bash -c 'source "$1"' bash "$leaf"
}

# Ivy Bridge "HD Graphics 4000" used to match the same name-based branch as
# Broadwell+ and get only intel-media-driver, which can't decode on Gen7 and
# leaves vaInitialize failing outright (confirmed on real Ivy Bridge hardware
# in basecamp/omarchy#7866). Installing both drivers means libva's own
# fallback probing picks the one that actually initializes, regardless of
# generation.
run_leaf
grep -q 'pkg-add intel-media-driver libva-intel-driver libvpl vpl-gpu-rt' "$call_log" ||
  fail "the leaf installs both VA-API drivers on Ivy Bridge HD Graphics 4000"
pass "the leaf installs both VA-API drivers on Ivy Bridge HD Graphics 4000"

# Haswell-ULT and other older parts that don't say "HD Graphics" or "gma" at
# all used to match neither branch and got no driver installed.
run_leaf "00:02.0 VGA compatible controller: Intel Corporation Haswell-ULT Integrated Graphics Controller (rev 0b)"
grep -q 'pkg-add intel-media-driver libva-intel-driver libvpl vpl-gpu-rt' "$call_log" ||
  fail "the leaf installs both VA-API drivers on hardware with no name match"
pass "the leaf installs both VA-API drivers on hardware with no name match"

run_leaf "00:02.0 VGA compatible controller: NVIDIA Corporation GA104M"
[[ -s $call_log ]] && fail "the leaf no-ops on non-Intel GPUs"
pass "the leaf no-ops on non-Intel GPUs"

run_migration() {
  : >"$call_log"
  PATH="$test_tmp/bin:$PATH" \
    CALL_LOG="$call_log" \
    TEST_LSPCI_LINE="${1-}" \
    bash -euo pipefail "$migration" >/dev/null
}

run_migration
grep -q 'pkg-add intel-media-driver libva-intel-driver libvpl vpl-gpu-rt' "$call_log" ||
  fail "the migration brings existing Intel installs onto both VA-API drivers"
pass "the migration brings existing Intel installs onto both VA-API drivers"

run_migration "00:02.0 VGA compatible controller: NVIDIA Corporation GA104M"
[[ -s $call_log ]] && fail "the migration no-ops on non-Intel GPUs"
pass "the migration no-ops on non-Intel GPUs"
