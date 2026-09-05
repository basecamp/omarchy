#!/bin/bash

# The screensaver launcher used to gate on `pgrep -f '[o]rg.omarchy.screensaver'`,
# which matches any process whose full command line contains that app-id string.
# An unrelated process with the string in argv made the launcher exit 0 without
# starting a screensaver (#10197). The gate must key on the process name
# `omarchy-screensaver` instead.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

launcher="$ROOT/bin/omarchy-launch-screensaver"

# Static: the false-positive-prone -f form must be gone; the name match must be
# present on the early-exit path.
if grep -E "pgrep[[:space:]]+-f[[:space:]]+['\"]?\\[o\\]rg\\.omarchy\\.screensaver" "$launcher" >/dev/null; then
  fail "omarchy-launch-screensaver no longer uses pgrep -f against the app-id string"
fi

grep -E 'pgrep[[:space:]]+-x[[:space:]]+omarchy-screensaver' "$launcher" >/dev/null ||
  fail "omarchy-launch-screensaver gates on pgrep -x omarchy-screensaver"

pass "launcher uses process-name match for the already-running check"

# Dynamic: a decoy process whose argv contains the app-id must not trip the
# new check, while the old -f form still would (documents the bug).
decoy_log=$(mktemp)
decoy_pid=""
cleanup() {
  [[ -n ${decoy_pid:-} ]] && kill "$decoy_pid" 2>/dev/null || true
  wait "$decoy_pid" 2>/dev/null || true
  rm -f "$decoy_log"
}
trap cleanup EXIT

# Process name is the interpreter ("bash"); the app-id only appears in argv.
# macOS sleep(1) rejects non-interval arguments, so a bash -c loop is portable.
bash -c 'while true; do sleep 30; done' org.omarchy.screensaver decoy-for-screensaver-test &
decoy_pid=$!

# Give the kernel a moment to publish the cmdline.
for _ in 1 2 3 4 5; do
  if pgrep -f 'org\.omarchy\.screensaver decoy-for-screensaver-test' >/dev/null; then
    break
  fi
  sleep 0.1
done

if ! pgrep -f 'org\.omarchy\.screensaver decoy-for-screensaver-test' >/dev/null; then
  fail "decoy process with app-id in argv is running for the regression probe"
fi

# Old check (would false-positive on this decoy).
if ! pgrep -f '[o]rg.omarchy.screensaver' >/dev/null; then
  fail "baseline: pgrep -f still matches a decoy argv containing the app-id"
fi

# New check must not match the decoy.
if pgrep -x omarchy-screensaver >/dev/null; then
  fail "pgrep -x omarchy-screensaver must not match a decoy process" \
    "matched pids: $(pgrep -x omarchy-screensaver | tr '\n' ' ')"
fi

pass "decoy argv containing org.omarchy.screensaver does not trip pgrep -x"

# Drive the launcher's early paths with stubs so we never talk to Hyprland.
tmp=$(mktemp -d)
trap 'cleanup; rm -rf "$tmp"' EXIT

cat >"$tmp/pgrep" <<'SH'
#!/bin/bash
# Record invocations; exit 1 (no match) unless -x omarchy-screensaver and the
# env asks us to pretend a real screensaver is up.
printf '%s\n' "$*" >>"${PGREP_LOG:?}"
if [[ ${SCREENSAVER_RUNNING:-0} == 1 && $1 == -x && $2 == omarchy-screensaver ]]; then
  echo 4242
  exit 0
fi
exit 1
SH
chmod +x "$tmp/pgrep"

cat >"$tmp/omarchy-toggle-enabled" <<'SH'
#!/bin/bash
# Always report screensaver enabled (toggle file absent).
exit 1
SH
chmod +x "$tmp/omarchy-toggle-enabled"

# Remaining helpers should never be reached on the already-running path.
for helper in omarchy-hyprland-monitor-focused xdg-terminal-exec hyprctl jq socat omarchy-notification-send; do
  cat >"$tmp/$helper" <<SH
#!/bin/bash
echo "unexpected call: $helper \$*" >&2
exit 99
SH
  chmod +x "$tmp/$helper"
done

export PATH="$tmp:$PATH"
export PGREP_LOG="$tmp/pgrep.log"
: >"$PGREP_LOG"

# Case 1: screensaver already running -> exit 0, no further helpers.
SCREENSAVER_RUNNING=1
set +e
out=$(SCREENSAVER_RUNNING=1 "$launcher" 2>&1)
rc=$?
set -e
(( rc == 0 )) || fail "launcher exits 0 when omarchy-screensaver is already running" "rc=$rc out=$out"
grep -q -- '-x omarchy-screensaver' "$PGREP_LOG" ||
  fail "already-running path queries pgrep -x omarchy-screensaver" "log: $(cat "$PGREP_LOG")"
pass "already-running path exits 0 via pgrep -x"

# Case 2: not running; decoy would have fooled -f, but we continue past the
# gate. Stub xdg-terminal-exec to an unsupported terminal so the script stops
# cleanly with exit 1 after the gate (proves the gate did not exit 0).
: >"$PGREP_LOG"
cat >"$tmp/xdg-terminal-exec" <<'SH'
#!/bin/bash
echo "SomeOtherTerminal"
SH
chmod +x "$tmp/xdg-terminal-exec"

cat >"$tmp/omarchy-hyprland-monitor-focused" <<'SH'
#!/bin/bash
echo "MONITOR"
SH
chmod +x "$tmp/omarchy-hyprland-monitor-focused"

cat >"$tmp/omarchy-notification-send" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$tmp/omarchy-notification-send"

set +e
out=$(SCREENSAVER_RUNNING=0 "$launcher" 2>&1)
rc=$?
set -e
(( rc == 1 )) || fail "launcher continues past the gate when no omarchy-screensaver process exists" "rc=$rc out=$out"
pass "absent screensaver process does not early-exit 0"
