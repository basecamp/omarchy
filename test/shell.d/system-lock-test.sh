#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

# Resolved before the mocks shadow it: the harness bounds the script with the
# real timeout, while the script under test sees the mock.
real_timeout=$(command -v timeout)

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mock_bin="$tmpdir/bin"
call_log="$tmpdir/calls"
mkdir -p "$mock_bin"

for command in hyprctl pkill timeout omarchy-notification-send; do
  cat >"$mock_bin/$command" <<'MOCK'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
MOCK
done

# Answers `lock status` the way the shell does. SECURE_AFTER is how many polls
# it takes to secure, so a lock that is still arming can be told apart from one
# that never will.
cat >"$mock_bin/omarchy-shell" <<'MOCK'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"

if [[ ${1:-} == "lock" && ${2:-} == "status" ]]; then
  polls=$(( $(cat "$POLL_COUNT" 2>/dev/null || echo 0) + 1 ))
  printf '%s' "$polls" >"$POLL_COUNT"
  if [[ ${SECURE_AFTER:-1} != never ]] && (( polls >= ${SECURE_AFTER:-1} )); then
    printf '{"secure":true,"requested":true}\n'
  else
    printf '{"secure":false,"requested":false}\n'
  fi
  exit 0
fi

if [[ ${1:-} == "lock" && ${2:-} == "lock" ]]; then
  [[ -n ${LOCK_REPLY:-} ]] && printf '%s\n' "$LOCK_REPLY"
  exit 0
fi
MOCK

cat >"$mock_bin/pgrep" <<'MOCK'
#!/bin/bash
exit 1
MOCK
chmod +x "$mock_bin"/*

run_lock() {
  local rc=0
  : >"$call_log"
  : >"$tmpdir/polls"
  PATH="$mock_bin:$PATH" CALL_LOG="$call_log" POLL_COUNT="$tmpdir/polls" \
    SECURE_AFTER="${SECURE_AFTER:-1}" LOCK_REPLY="${LOCK_REPLY:-}" \
    "$real_timeout" -k 5s 40s "$ROOT/bin/omarchy-system-lock" 2>"$tmpdir/stderr" || rc=$?
  return "$rc"
}

rc=0
run_lock || rc=$?
(( rc == 0 )) || fail "system lock succeeds once the session is secure" "exit $rc, $(<"$tmpdir/stderr")"
pass "system lock succeeds once the session is secure"

mapfile -t shutdown < <(rg '^(pkill|timeout) ' "$call_log")
[[ ${shutdown[0]} == "pkill -x ttfx" ]] ||
  fail "system lock stops ttfx before closing its terminal" "calls: ${shutdown[*]}"
[[ ${shutdown[1]} == "timeout 1s pidwait -x ttfx" ]] ||
  fail "system lock waits for ttfx to exit" "calls: ${shutdown[*]}"
[[ ${shutdown[2]} == "pkill -f [o]rg.omarchy.screensaver" ]] ||
  fail "system lock closes the screensaver terminal after ttfx exits" "calls: ${shutdown[*]}"
pass "system lock waits for ttfx before closing its terminal"

# The lock is secured after the request returns, so a session still arming must
# not be mistaken for one that failed.
rc=0
SECURE_AFTER=3 run_lock || rc=$?
(( rc == 0 )) || fail "system lock waits for a session that is still arming" "exit $rc"
pass "system lock waits for a session that is still arming"

# The shell reports a lock it can never perform on stdout, with a zero exit.
rc=0
LOCK_REPLY=missing-pam run_lock || rc=$?
(( rc == 1 )) || fail "system lock fails when no lock screen is configured" "exit $rc"
grep -q "no lock screen is configured" "$tmpdir/stderr" ||
  fail "system lock says why the session was not locked" "$(<"$tmpdir/stderr")"
grep -q "^omarchy-notification-send .*Screen did not lock" "$call_log" ||
  fail "system lock warns on screen when it could not lock"
pass "system lock fails when no lock screen is configured"

# The earliest exit in the script, so the one most likely to strand the work
# that has to happen whether or not the session ends up secured.
rg -q '^pkill -f \[o\]rg\.omarchy\.screensaver$' "$call_log" ||
  fail "a lock the shell refuses still tears down the screensaver"
rg -q '^hyprctl switchxkblayout all 0$' "$call_log" ||
  fail "a lock the shell refuses still resets the keyboard layout"
pass "a lock the shell refuses still runs the rest of the lock sequence"

# The failure this exists to catch: the request is accepted, nothing secures,
# and the old script reported success anyway.
started=$SECONDS
rc=0
SECURE_AFTER=never run_lock || rc=$?
elapsed=$((SECONDS - started))

(( rc == 1 )) || fail "system lock fails when the session never becomes secure" "exit $rc"
(( rc != 124 && rc != 137 )) || fail "system lock gives up on its own" "still running after ${elapsed}s"
pass "system lock fails when the session never becomes secure"

grep -q "did not secure the session" "$tmpdir/stderr" ||
  fail "system lock reports the deadline it gave up on" "$(<"$tmpdir/stderr")"
pass "system lock reports the deadline it gave up on"

(( $(grep -c '^omarchy-shell lock lock$' "$call_log") > 1 )) ||
  fail "system lock re-requests a lock the shell dropped" "$(grep -c '^omarchy-shell lock lock$' "$call_log") request(s)"
pass "system lock re-requests a lock the shell dropped"

# Locking 1Password and closing the screensaver still have to happen even when
# the session itself could not be secured.
rg -q '^pkill -f \[o\]rg\.omarchy\.screensaver$' "$call_log" ||
  fail "system lock still closes the screensaver when the lock fails"
pass "system lock still closes the screensaver when the lock fails"
