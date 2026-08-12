#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

write_stub() {
  local name="$1"
  local body="$2"

  cat >"$stub_bin/$name" <<SH
#!/bin/bash
$body
SH
  chmod +x "$stub_bin/$name"
}

run_pkg_prune() {
  PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-update-pkg-prune"
}

# Pin the keep count above one.
write_stub sudo 'printf "%s\n" "$*" >"$PACCACHE_LOG"; exit 0'

PACCACHE_LOG="$test_tmp/args" run_pkg_prune >"$test_tmp/prune.out" 2>&1
grep -q 'paccache' "$test_tmp/args" || fail "cache prune runs paccache"
grep -qE 'paccache .*-rk2' "$test_tmp/args" ||
  fail "cache prune keeps more than one version" "$(cat "$test_tmp/args")"
pass "cache prune leaves a rollback version to spare"

# Housekeeping failure must not abort the update.
write_stub sudo 'exit 1'
run_pkg_prune >"$test_tmp/fail.out" 2>&1 ||
  fail "cache prune survives paccache failure"
grep -q 'Could not prune the package cache' "$test_tmp/fail.out" ||
  fail "cache prune warns when it fails" "$(cat "$test_tmp/fail.out")"
pass "cache prune warns but does not abort the update"

# Ordering is the whole guarantee: rollback before the packages update, space
# before the snapshot.
line_of() {
  grep -n "^[[:space:]]*$1\b" "$ROOT/bin/omarchy-update" | head -1 | cut -d: -f1
}

prune_line=$(line_of omarchy-update-pkg-prune)
snapshot_line=$(line_of omarchy-snapshot)
pkgs_line=$(line_of omarchy-update-system-pkgs)
[[ -n $prune_line && -n $snapshot_line && -n $pkgs_line ]] ||
  fail "omarchy-update runs the cache prune, the snapshot, and the packages update"

(( prune_line < pkgs_line )) ||
  fail "cache prune runs before the packages update" "prune: $prune_line, packages: $pkgs_line"
pass "cache prune runs before the packages update"

(( prune_line < snapshot_line )) ||
  fail "cache prune runs before the snapshot" "prune: $prune_line, snapshot: $snapshot_line"
pass "cache prune runs before the snapshot pins what it removes"
