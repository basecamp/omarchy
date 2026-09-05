#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration=$(grep -rl 'Remove leftover world-readable diagnostics files from /tmp' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "legacy diagnostics /tmp migration exists"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

run_migration() {
  OMARCHY_LEGACY_DIAGNOSTICS_TMP="$tmp" bash -euo pipefail "$migration" >/dev/null
}

# Own leftovers are removed.
: >"$tmp/omarchy-debug.log"
: >"$tmp/upload-log.txt"
: >"$tmp/system-info.txt"
chmod 644 "$tmp/omarchy-debug.log" "$tmp/upload-log.txt" "$tmp/system-info.txt"
run_migration
[[ ! -e $tmp/omarchy-debug.log ]] || fail "removes omarchy-debug.log"
[[ ! -e $tmp/upload-log.txt ]] || fail "removes upload-log.txt"
[[ ! -e $tmp/system-info.txt ]] || fail "removes system-info.txt"
pass "removes owned legacy diagnostics files from the staging dir"

# Idempotent when nothing is left.
run_migration
pass "no-ops when the legacy files are already gone"

# Unrelated files in the same directory stay put.
: >"$tmp/omarchy-debug.log"
: >"$tmp/keep-me.txt"
run_migration
[[ ! -e $tmp/omarchy-debug.log ]] || fail "still removes the legacy name"
[[ -f $tmp/keep-me.txt ]] || fail "leaves unrelated files alone"
pass "leaves unrelated files in the same directory alone"

# Symlinks at the legacy names are left alone (do not follow / unlink the target).
: >"$tmp/real-target.txt"
ln -s "$tmp/real-target.txt" "$tmp/omarchy-debug.log"
run_migration
[[ -L $tmp/omarchy-debug.log ]] || fail "leaves a symlink at the legacy name"
[[ -f $tmp/real-target.txt ]] || fail "does not unlink a symlink target"
pass "refuses to remove a symlink at a legacy name"

# A non-owned regular file is left alone when we can create one (skip if not root
# and the filesystem forbids alien ownership — the common case is a no-op create).
other="$tmp/upload-log.txt"
: >"$other"
if chown nobody "$other" 2>/dev/null; then
  run_migration
  [[ -f $other ]] || fail "leaves a file owned by another user"
  pass "leaves a legacy file owned by another user"
else
  rm -f "$other"
  pass "skips other-owner check when chown is unavailable"
fi
