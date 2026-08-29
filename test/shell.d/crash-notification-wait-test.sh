#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"

# Create a stub qs that sleeps to simulate an unresponsive IPC call.
# The real omarchy-shell will invoke `timeout ... "$OMARCHY_SHELL_IPC_TIMEOUT" qs ...`
cat >"$TMPDIR/bin/qs" <<'SH'
#!/bin/bash
exec sleep 10
SH

cat >"$TMPDIR/bin/busctl" <<'SH'
#!/bin/bash
exit 1
SH

chmod +x "$TMPDIR/bin/qs" "$TMPDIR/bin/busctl"

# Test omarchy-notification-wait timeout with wall-clock deadline.
# A requested 1s timeout must complete in ~1-2 seconds even when omarchy-shell stalls.
start_time=$SECONDS
status=0
OMARCHY_PATH="$ROOT" PATH="$TMPDIR/bin:$ROOT/bin:$PATH" "$ROOT/bin/omarchy-notification-wait" 1 >/dev/null 2>&1 || status=$?
elapsed=$((SECONDS - start_time))

(( status != 0 )) || fail "omarchy-notification-wait returns non-zero on timeout"
(( elapsed < 4 )) || fail "omarchy-notification-wait took ${elapsed}s, exceeding wall-clock timeout budget"
pass "omarchy-notification-wait enforces wall-clock deadline when shell stalls"

# Test stderr drop logging in omarchy-crash-watch
watch_bin="$TMPDIR/watch-bin"
watch_home="$TMPDIR/watch-home"
JOURNAL_ENTRIES="$TMPDIR/journal-entries"
STDERR_LOG="$TMPDIR/stderr-log"

mkdir -p "$watch_bin" "$watch_home"

cat >"$watch_bin/journalctl" <<'SH'
#!/bin/bash
cat "$JOURNAL_ENTRIES"
SH

cat >"$watch_bin/omarchy-default-agent" <<'SH'
#!/bin/bash
echo claude
SH

cat >"$watch_bin/omarchy-notification-wait" <<'SH'
#!/bin/bash
exit 1
SH

chmod +x "$watch_bin/journalctl" "$watch_bin/omarchy-default-agent" "$watch_bin/omarchy-notification-wait"

require_command jq

jq -cn --arg uid "$UID" \
  '{_UID: $uid, COREDUMP_COMM: "testapp", COREDUMP_PID: "1234",
    COREDUMP_EXE: "/usr/bin/testapp", COREDUMP_SIGNAL_NAME: "SIGSEGV"}' >"$JOURNAL_ENTRIES"

PATH="$watch_bin:$ROOT/bin:$PATH" \
JOURNAL_ENTRIES="$JOURNAL_ENTRIES" \
HOME="$watch_home" \
  "$ROOT/bin/omarchy-crash-watch" 2>"$STDERR_LOG" || true

grep -Fq "omarchy-crash-watch: notification server unavailable, dropped crash toast for testapp" "$STDERR_LOG" ||
  fail "omarchy-crash-watch logs dropped crash notifications to stderr"
pass "omarchy-crash-watch logs dropped crash notifications to stderr"
