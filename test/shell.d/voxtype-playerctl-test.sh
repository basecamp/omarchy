#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Voxtype pause_media shells out to playerctl. #9244 adds it to a fresh
# omarchy-voxtype-install; this also covers people who already installed Voxtype.

install="$ROOT/bin/omarchy-voxtype-install"
migration=$(grep -l "Install playerctl for existing Voxtype installs" "$ROOT"/migrations/*.sh | head -1)

grep -q 'omarchy-pkg-add wtype playerctl voxtype-bin' "$install" ||
  fail "voxtype-install installs playerctl with voxtype"
pass "voxtype-install installs playerctl with voxtype"

[[ -n $migration ]] || fail "a migration installs playerctl for existing Voxtype installs"
[[ ! -x $migration ]] || fail "the migration is not executable"
! grep -q '^#!' "$migration" || fail "the migration has no shebang"
pass "a migration installs playerctl for existing Voxtype installs"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"

cat >"$test_tmp/bin/omarchy-pkg-present" <<'SH'
#!/bin/bash
[[ ${TEST_VOXTYPE_PRESENT:-0} == 1 ]]
SH

cat >"$test_tmp/bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'pkg-add %s\n' "$*" >>"$CALL_LOG"
SH

chmod +x "$test_tmp/bin"/*

run_migration() {
  : >"$CALL_LOG"
  PATH="$test_tmp/bin:$PATH" CALL_LOG="$CALL_LOG" TEST_VOXTYPE_PRESENT="${1:-0}" \
    bash -euo pipefail "$migration" >/dev/null
}

CALL_LOG="$test_tmp/calls.log"

run_migration 0
[[ ! -s $CALL_LOG ]] || fail "migration no-ops when Voxtype is not installed"
pass "migration no-ops when Voxtype is not installed"

run_migration 1
grep -qxF 'pkg-add playerctl' "$CALL_LOG" ||
  fail "migration installs playerctl when Voxtype is installed"
pass "migration installs playerctl when Voxtype is installed"
