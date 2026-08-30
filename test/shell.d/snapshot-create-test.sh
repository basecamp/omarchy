#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

snapshot="$ROOT/bin/omarchy-snapshot"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
chmod +x "$fake_bin/sudo"

cat >"$fake_bin/omarchy-cmd-missing" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod +x "$fake_bin/omarchy-cmd-missing"

cat >"$fake_bin/omarchy-version" <<'STUB'
#!/bin/bash
echo 4.0.0
STUB
chmod +x "$fake_bin/omarchy-version"

# Snapper with no configs: list-configs prints only the CSV header.
cat >"$fake_bin/snapper" <<'STUB'
#!/bin/bash
printf 'snapper %s\n' "$*" >>"$TEST_LOG"
if [[ "$*" == *"list-configs"* ]]; then
  echo "config,subvolume"
fi
STUB
chmod +x "$fake_bin/snapper"

# A snapshot that silently creates nothing reads as a successful snapshot, so
# an unconfigured Snapper has to fail loudly instead of passing for a backup.
: >"$test_tmp/calls.log"
set +e
stderr=$(OMARCHY_SNAPSHOT_FSTYPE=btrfs TEST_LOG="$test_tmp/calls.log" PATH="$fake_bin:$PATH" \
  bash "$snapshot" create 2>&1 >/dev/null)
status=$?
set -e

(( status != 0 )) || fail "snapshot create fails when Snapper has no configs"
grep -qF 'No Snapper configs found' <<<"$stderr" ||
  fail "snapshot create reports that no snapshot was created" "$stderr"
! grep -q '^snapper -c .* create ' "$test_tmp/calls.log" ||
  fail "snapshot create does not invent a config to snapshot"
pass "snapshot create fails loudly when Snapper is installed but unconfigured"

cat >"$fake_bin/snapper" <<'STUB'
#!/bin/bash
printf 'snapper %s\n' "$*" >>"$TEST_LOG"
if [[ "$*" == *"list-configs"* ]]; then
  echo "config,subvolume"
  echo "root,/"
fi
STUB
chmod +x "$fake_bin/snapper"

: >"$test_tmp/calls.log"
OMARCHY_SNAPSHOT_FSTYPE=btrfs TEST_LOG="$test_tmp/calls.log" PATH="$fake_bin:$PATH" \
  bash "$snapshot" create >/dev/null

grep -qFx 'snapper -c root create -c number -d 4.0.0' "$test_tmp/calls.log" ||
  fail "snapshot create snapshots each configured subvolume" "$(cat "$test_tmp/calls.log")"
grep -qFx 'snapper -c root cleanup number' "$test_tmp/calls.log" ||
  fail "snapshot create prunes older snapshots"
pass "snapshot create snapshots every configured Snapper config"

# Snapper being deliberately absent is the one skip that stays quiet, and the
# update has to keep treating it as such.
cat >"$fake_bin/omarchy-cmd-missing" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$fake_bin/omarchy-cmd-missing"

set +e
OMARCHY_SNAPSHOT_FSTYPE=btrfs TEST_LOG="$test_tmp/calls.log" PATH="$fake_bin:$PATH" \
  bash "$snapshot" create >/dev/null 2>&1
status=$?
set -e

(( status == 127 )) || fail "snapshot create exits 127 without snapper" "got $status"
grep -qF 'omarchy-snapshot create || (($? == 127))' "$ROOT/bin/omarchy-update" ||
  fail "update ignores only the missing-snapper exit code"
pass "snapshot create keeps the quiet 127 path for systems without snapper"

# A non-Btrfs root uses Timeshift instead of Snapper. Snapshot create has to
# route there, refusing to run when unconfigured and calling into it when a
# snapshot location exists.
cat >"$fake_bin/omarchy-cmd-missing" <<'STUB'
#!/bin/bash
# The first argument is the command whose presence is being checked. In this
# block every dependency is treated as present.
exit 1
STUB
chmod +x "$fake_bin/omarchy-cmd-missing"

cat >"$fake_bin/timeshift" <<'STUB'
#!/bin/bash
printf 'timeshift %s\n' "$*" >>"$TEST_LOG"
STUB
chmod +x "$fake_bin/timeshift"

: >"$test_tmp/calls.log"
set +e
stderr=$(OMARCHY_SNAPSHOT_FSTYPE=ext4 OMARCHY_TIMESHIFT_CONFIG="$test_tmp/no-config.json" \
  TEST_LOG="$test_tmp/calls.log" PATH="$fake_bin:$PATH" \
  bash "$snapshot" create 2>&1 >/dev/null)
status=$?
set -e

(( status != 0 )) || fail "snapshot create fails on non-Btrfs roots without a configured Timeshift"
grep -qF "run 'sudo timeshift-wizard' once" <<<"$stderr" ||
  fail "snapshot create tells the user to configure Timeshift" "$stderr"
! grep -q '^timeshift ' "$test_tmp/calls.log" ||
  fail "snapshot create does not run Timeshift before it is configured"
pass "snapshot create fails loudly on non-Btrfs roots without Timeshift configured"

cat >"$test_tmp/timeshift.json" <<'JSON'
{}
JSON

: >"$test_tmp/calls.log"
OMARCHY_SNAPSHOT_FSTYPE=ext4 OMARCHY_TIMESHIFT_CONFIG="$test_tmp/timeshift.json" \
  TEST_LOG="$test_tmp/calls.log" PATH="$fake_bin:$PATH" \
  bash "$snapshot" create >/dev/null

grep -qF 'timeshift --create --comments pre-update 4.0.0' "$test_tmp/calls.log" ||
  fail "snapshot create runs Timeshift on non-Btrfs roots" "$(cat "$test_tmp/calls.log")"
pass "snapshot create uses Timeshift for non-Btrfs roots"

# The quattro upgrade runs under set -e, so a failed snapshot has to be warned
# past there too or it aborts the whole upgrade at the snapshot step.
grep -qF 'omarchy-snapshot create || (($? == 127))' "$ROOT/bin/omarchy-upgrade-to-quattro" ||
  fail "upgrade ignores only the missing-snapper exit code"
grep -qF 'Continuing the upgrade without a snapshot' "$ROOT/bin/omarchy-upgrade-to-quattro" ||
  fail "upgrade continues past a failed snapshot instead of aborting"
pass "upgrade to quattro survives a failed snapshot without passing it off"
