#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leak_migration=$(grep -rl 'timeline snapshots leaked by earlier defaults' "$ROOT/migrations" | head -n 1 || true)
[[ -n $leak_migration ]] || fail "Snapper timeline leak migration exists"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
chmod +x "$fake_bin/sudo"

cat >"$fake_bin/snapper" <<'STUB'
#!/bin/bash
printf 'snapper %s\n' "$*" >>"$TEST_LOG"
if [[ "$*" == *"--csvout list"* ]]; then
  echo "number,cleanup"
  for i in $(seq 1 45); do
    echo "$i,timeline"
  done
  echo "100,number"
  echo "101,"
fi
STUB
chmod +x "$fake_bin/snapper"

snapper_config="$test_tmp/root"
printf '%s\n' 'TIMELINE_CREATE="no"' 'NUMBER_CLEANUP="yes"' >"$snapper_config"

TEST_LOG="$test_tmp/calls.log" \
PATH="$fake_bin:$PATH" \
OMARCHY_SNAPPER_CONFIG_PATH="$snapper_config" \
  bash -euo pipefail "$leak_migration" >/dev/null

deletes=$(grep -c '^snapper -c root delete ' "$test_tmp/calls.log" || true)
[[ $deletes -eq 3 ]] || fail "leak migration deletes snapshots in batches" "expected 3 delete calls, got $deletes"

first_batch=$(grep -m1 '^snapper -c root delete ' "$test_tmp/calls.log")
[[ $first_batch == "snapper -c root delete $(seq -s ' ' 1 20)" ]] || fail "leak migration caps delete batches at 20 snapshots" "$first_batch"

last_batch=$(grep '^snapper -c root delete ' "$test_tmp/calls.log" | tail -n 1)
[[ $last_batch == "snapper -c root delete $(seq -s ' ' 41 45)" ]] || fail "leak migration deletes the final partial batch" "$last_batch"

! grep -E '^snapper -c root delete .*\b(100|101)\b' "$test_tmp/calls.log" || fail "leak migration only deletes timeline snapshots"
pass "leak migration removes leaked timeline snapshots in batches and keeps the rest"

# omarchy-migrate runs under set -e, so a batch that dies on a DBus timeout
# would otherwise abort the run and skip every migration queued behind it.
: >"$test_tmp/calls.log"
printf '%s\n' 'TIMELINE_CREATE="no"' 'NUMBER_CLEANUP="yes"' >"$snapper_config"

cat >"$fake_bin/snapper" <<'STUB'
#!/bin/bash
printf 'snapper %s\n' "$*" >>"$TEST_LOG"
if [[ "$*" == *"--csvout list"* ]]; then
  echo "number,cleanup"
  for i in $(seq 1 45); do
    echo "$i,timeline"
  done
  exit 0
fi
echo "failure: dbus timeout" >&2
exit 1
STUB

TEST_LOG="$test_tmp/calls.log" \
PATH="$fake_bin:$PATH" \
OMARCHY_SNAPPER_CONFIG_PATH="$snapper_config" \
  bash -euo pipefail "$leak_migration" >/dev/null 2>&1 ||
  fail "leak migration survives a failed delete batch"

deletes=$(grep -c '^snapper -c root delete ' "$test_tmp/calls.log" || true)
[[ $deletes -eq 3 ]] || fail "leak migration keeps draining after a failed batch" "expected 3 delete calls, got $deletes"
pass "leak migration tolerates a batch that fails partway"

: >"$test_tmp/calls.log"
printf '%s\n' 'TIMELINE_CREATE="yes"' >"$snapper_config"

TEST_LOG="$test_tmp/calls.log" \
PATH="$fake_bin:$PATH" \
OMARCHY_SNAPPER_CONFIG_PATH="$snapper_config" \
  bash -euo pipefail "$leak_migration" >/dev/null

[[ ! -s $test_tmp/calls.log ]] || fail "leak migration leaves deliberate timeline setups alone"
pass "leak migration skips systems where timeline snapshots are intentional"

: >"$test_tmp/calls.log"

TEST_LOG="$test_tmp/calls.log" \
PATH="$fake_bin:$PATH" \
OMARCHY_SNAPPER_CONFIG_PATH="$test_tmp/missing" \
  bash -euo pipefail "$leak_migration" >/dev/null

[[ ! -s $test_tmp/calls.log ]] || fail "leak migration skips systems without a Snapper root config"
pass "leak migration is a no-op without Snapper configured"
