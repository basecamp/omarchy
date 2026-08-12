#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

config_script="$ROOT/install/config/binfmt.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

write_conf() {
  # Shaped like the qemu-user-static-binfmt package's own registrations:
  # a magic/mask binfmt_misc line ending in the flags field.
  printf ':qemu-%s:M::magic:mask:/usr/bin/qemu-%s-static:FP\n' "$1" "$1" >"$2"
}

# The config script rewrites every qemu-*-static registration the package
# ships, leaving the rest of each line untouched, and skips anything in the
# source directory that isn't a qemu static registration.
source_dir="$test_tmp/lib-binfmt.d"
dest_dir="$test_tmp/etc-binfmt.d"
mkdir -p "$source_dir"
write_conf aarch64 "$source_dir/qemu-aarch64-static.conf"
write_conf arm "$source_dir/qemu-arm-static.conf"
printf 'unrelated\n' >"$source_dir/other.conf"

OMARCHY_BINFMT_SOURCE_DIR="$source_dir" OMARCHY_BINFMT_DIR="$dest_dir" \
  bash -euo pipefail "$config_script" >/dev/null

grep -qFx ':qemu-aarch64:M::magic:mask:/usr/bin/qemu-aarch64-static:OCF' "$dest_dir/qemu-aarch64-static.conf" ||
  fail "binfmt config overrides aarch64 flags with OCF"
grep -qFx ':qemu-arm:M::magic:mask:/usr/bin/qemu-arm-static:OCF' "$dest_dir/qemu-arm-static.conf" ||
  fail "binfmt config overrides arm flags with OCF"
[[ -f $dest_dir/other.conf ]] && fail "binfmt config copies files that aren't qemu static registrations"
pass "binfmt config overrides every qemu static registration with OCF flags"

# Re-running must stay clean and keep producing OCF.
OMARCHY_BINFMT_SOURCE_DIR="$source_dir" OMARCHY_BINFMT_DIR="$dest_dir" \
  bash -euo pipefail "$config_script" >/dev/null
grep -qFx ':qemu-aarch64:M::magic:mask:/usr/bin/qemu-aarch64-static:OCF' "$dest_dir/qemu-aarch64-static.conf" ||
  fail "binfmt config is idempotent"
pass "binfmt config is idempotent"

# A dev checkout may run before qemu-user-static-binfmt is installed, so the
# source directory can be empty; the script must not fail on the unmatched
# glob.
empty_source_dir="$test_tmp/empty-lib-binfmt.d"
empty_dest_dir="$test_tmp/empty-etc-binfmt.d"
mkdir -p "$empty_source_dir"
OMARCHY_BINFMT_SOURCE_DIR="$empty_source_dir" OMARCHY_BINFMT_DIR="$empty_dest_dir" \
  bash -euo pipefail "$config_script" >/dev/null ||
  fail "binfmt config tolerates a source directory with no qemu registrations"
pass "binfmt config tolerates a source directory with no qemu registrations"

# The migration that fixes existing installs.
migration=$(grep -rl 'Fix QEMU binfmt registration' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "binfmt migration exists"

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
chmod +x "$fake_bin/sudo"

cat >"$fake_bin/systemctl" <<'STUB'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$TEST_LOG"
STUB
chmod +x "$fake_bin/systemctl"

run_migration() {
  TEST_LOG="$test_tmp/calls.log" \
  PATH="$fake_bin:$PATH" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_BINFMT_SOURCE_DIR="$source_dir" \
  OMARCHY_BINFMT_DIR="$1" \
    bash -euo pipefail "$migration" >/dev/null
}

# An install still carrying the old FP flags gets rewritten and the binfmt
# service restarted to pick it up.
stale_dir="$test_tmp/stale-etc-binfmt.d"
mkdir -p "$stale_dir"
write_conf aarch64 "$stale_dir/qemu-aarch64-static.conf"

: >"$test_tmp/calls.log"
run_migration "$stale_dir"

grep -qFx ':qemu-aarch64:M::magic:mask:/usr/bin/qemu-aarch64-static:OCF' "$stale_dir/qemu-aarch64-static.conf" ||
  fail "binfmt migration rewrites a stale registration"
grep -qFx 'systemctl restart systemd-binfmt.service' "$test_tmp/calls.log" ||
  fail "binfmt migration restarts systemd-binfmt.service"
pass "binfmt migration fixes existing installs and restarts the binfmt service"

# Already-fixed installs are left alone.
: >"$test_tmp/calls.log"
run_migration "$stale_dir"
[[ ! -s $test_tmp/calls.log ]] || fail "binfmt migration skips already-fixed installs"
pass "binfmt migration is a no-op once the registration already carries OCF"

# A partially-fixed install (say aarch64 was hand-edited already, or the
# package added an architecture after this migration last ran for this user)
# must still be caught: the check has to look at every architecture the
# package registers, not just one.
partial_dir="$test_tmp/partial-etc-binfmt.d"
mkdir -p "$partial_dir"
printf ':qemu-aarch64:M::magic:mask:/usr/bin/qemu-aarch64-static:OCF\n' >"$partial_dir/qemu-aarch64-static.conf"
write_conf arm "$partial_dir/qemu-arm-static.conf"

: >"$test_tmp/calls.log"
run_migration "$partial_dir"

grep -qFx ':qemu-arm:M::magic:mask:/usr/bin/qemu-arm-static:OCF' "$partial_dir/qemu-arm-static.conf" ||
  fail "binfmt migration fixes an architecture still on FP even when another already carries OCF"
grep -qFx 'systemctl restart systemd-binfmt.service' "$test_tmp/calls.log" ||
  fail "binfmt migration restarts systemd-binfmt.service for a partially-fixed install"
pass "binfmt migration checks every registered architecture, not just one"

# A dev checkout carries migrations from a release whose install scripts the
# checked-out tree may not have yet, and omarchy-migrate runs under set -e.
: >"$test_tmp/calls.log"
missing_dir="$test_tmp/missing-etc-binfmt.d"
TEST_LOG="$test_tmp/calls.log" \
PATH="$fake_bin:$PATH" \
OMARCHY_PATH="$test_tmp/empty" \
OMARCHY_BINFMT_SOURCE_DIR="$source_dir" \
OMARCHY_BINFMT_DIR="$missing_dir" \
  bash -euo pipefail "$migration" >/dev/null ||
  fail "binfmt migration survives a tree without the binfmt config script"
[[ ! -s $test_tmp/calls.log ]] || fail "binfmt migration touches nothing without the binfmt config script"
pass "binfmt migration is a no-op when the binfmt config script is missing"
