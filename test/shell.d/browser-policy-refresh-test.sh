#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)

# The stub browser below is built not to die on TERM, so if an assertion fails
# before the refresh is bounded it would outlive this file.
cleanup() {
  local pidfile=$tmpdir/m2/chromium.pid pid
  if [[ -f $pidfile ]]; then
    while read -r pid; do kill -9 "$pid" 2>/dev/null || true; done < "$pidfile"
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

stub_bin=$tmpdir/bin
mkdir -p "$stub_bin"

# Only the browsers listed here answer pgrep, so a browser actually installed on
# the machine running this test is never probed and never launched.
running=$tmpdir/running
: > "$running"

cat > "$stub_bin/pgrep" <<'STUB'
#!/bin/bash
grep -Fxq -- "${!#}" "$RUNNING_BROWSERS"
STUB

cat > "$stub_bin/omarchy-theme-set-browser-policy" <<'STUB'
#!/bin/bash
printf '%s\n' "$1" > "$POLICY_MARKER"
exit "${POLICY_STATUS:-0}"
STUB

# Exits immediately, like a browser that takes the policy handoff and returns.
cat > "$stub_bin/brave" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" > "$REFRESH_MARKER_DIR/brave"
STUB

# Never returns, and ignores TERM: plain `timeout` waits out a child like this
# instead of bounding it, which is why the refresh needs a kill fallback.
cat > "$stub_bin/chromium" <<'STUB'
#!/bin/bash
trap '' TERM
sleep 120 &
printf '%s\n%s\n' "$$" "$!" > "$REFRESH_MARKER_DIR/chromium.pid"
wait
STUB

chmod +x "$stub_bin"/*

run_theme_set() {
  local markers=$1 rc=0
  mkdir -p "$markers"
  RUNNING_BROWSERS=$running \
    POLICY_MARKER=$tmpdir/policy \
    POLICY_STATUS=${POLICY_STATUS:-0} \
    REFRESH_MARKER_DIR=$markers \
    OMARCHY_PATH=$ROOT \
    HOME=$tmpdir \
    PATH="$stub_bin:$ROOT/bin:/usr/bin:/bin" \
    timeout -k 5s 30s bash "$ROOT/bin/omarchy-theme-set-browser" >/dev/null 2>&1 || rc=$?
  return "$rc"
}

# A browser that answers promptly still gets its refresh.
printf 'brave\n' > "$running"
rc=0
run_theme_set "$tmpdir/m1" || rc=$?
(( rc == 0 )) || fail "theme-set-browser succeeds when a running browser refreshes cleanly" "exit $rc"
[[ -f $tmpdir/m1/brave ]] || fail "theme-set-browser refreshes a running browser"
grep -q -- '--refresh-platform-policy' "$tmpdir/m1/brave" ||
  fail "theme-set-browser passes --refresh-platform-policy" "$(<"$tmpdir/m1/brave")"
pass "theme-set-browser refreshes a running browser"

# A browser that never returns must not hold up the theme change, and must not
# take the browsers listed after it down with it.
printf 'chromium\nbrave\n' > "$running"
started=$SECONDS
rc=0
run_theme_set "$tmpdir/m2" || rc=$?
elapsed=$((SECONDS - started))

# run_theme_set is itself bounded, so an unbounded refresh fails here instead of
# hanging the suite.
(( rc != 124 && rc != 137 )) ||
  fail "theme-set-browser converges when a browser refresh never returns" "still running after ${elapsed}s"
pass "theme-set-browser converges when a browser refresh never returns"

[[ -f $tmpdir/m2/brave ]] ||
  fail "theme-set-browser still refreshes later browsers after one hangs"
pass "theme-set-browser still refreshes later browsers after one hangs"

(( rc == 0 )) ||
  fail "a timed-out browser refresh does not fail the theme change" "exit $rc"
pass "a timed-out browser refresh does not fail the theme change"

# The whole tree, not just the process timeout signalled: a browser leaves
# children behind, and they are what turns a bounded refresh into litter.
sleep 1
while read -r hung_pid; do
  if kill -0 "$hung_pid" 2>/dev/null; then
    fail "a timed-out browser refresh leaves no process behind" "pid $hung_pid still running"
  fi
done < "$tmpdir/m2/chromium.pid"
pass "a timed-out browser refresh leaves no process behind"

# Policy writing owns the exit status; refreshing never did.
printf 'brave\n' > "$running"
rc=0
POLICY_STATUS=1 run_theme_set "$tmpdir/m3" || rc=$?
(( rc == 1 )) || fail "a failed policy write still fails theme-set-browser" "exit $rc"
[[ -f $tmpdir/m3/brave ]] || fail "a failed policy write still refreshes running browsers"
pass "a failed policy write still fails theme-set-browser"
