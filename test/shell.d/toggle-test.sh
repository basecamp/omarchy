#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=""

export PATH="$ROOT/bin:$PATH"

cleanup() {
  if [[ -n $TMPDIR && -d $TMPDIR ]]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

TMPDIR=$(mktemp -d)
test_home="$TMPDIR/home"
flag="$test_home/.local/state/omarchy/toggles/example"
bar_flag="$test_home/.local/state/omarchy/toggles/bar-off"
stub_bin="$TMPDIR/bin"
ipc_log="$TMPDIR/ipc.log"

mkdir -p "$stub_bin"
cat >"$stub_bin/omarchy-shell" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$IPC_LOG"
SH
chmod +x "$stub_bin/omarchy-shell"
export IPC_LOG="$ipc_log"
export PATH="$stub_bin:$PATH"

HOME="$test_home" omarchy-toggle example on
[[ -f $flag ]] || fail "generic toggle enables explicit on state"
pass "generic toggle enables explicit on state"

HOME="$test_home" omarchy-toggle example on
[[ -f $flag ]] || fail "generic toggle on is idempotent"
pass "generic toggle on is idempotent"

HOME="$test_home" omarchy-toggle example off
[[ ! -f $flag ]] || fail "generic toggle disables explicit off state"
pass "generic toggle disables explicit off state"

HOME="$test_home" omarchy-toggle example
[[ -f $flag ]] || fail "generic toggle flips disabled state on"
pass "generic toggle flips disabled state on"

HOME="$test_home" omarchy-toggle example toggle
[[ ! -f $flag ]] || fail "generic toggle flips enabled state off"
pass "generic toggle flips enabled state off"

HOME="$test_home" omarchy-toggle-bar off
[[ -f $bar_flag ]] || fail "bar off enables bar-off toggle"
pass "bar off enables bar-off toggle"

HOME="$test_home" omarchy-toggle-bar off
[[ -f $bar_flag ]] || fail "bar off is idempotent"
pass "bar off is idempotent"

HOME="$test_home" omarchy-toggle-bar on
[[ ! -f $bar_flag ]] || fail "bar on disables bar-off toggle"
pass "bar on disables bar-off toggle"

HOME="$test_home" omarchy-toggle-bar on
[[ ! -f $bar_flag ]] || fail "bar on is idempotent"
pass "bar on is idempotent"

HOME="$test_home" omarchy-toggle-bar
[[ -f $bar_flag ]] || fail "bar default action hides a visible bar"
pass "bar default action hides a visible bar"

HOME="$test_home" omarchy-toggle-bar toggle
[[ ! -f $bar_flag ]] || fail "bar explicit toggle reveals a hidden bar"
pass "bar explicit toggle reveals a hidden bar"

invalid_output="$TMPDIR/invalid.out"
if HOME="$test_home" omarchy-toggle-bar invalid >"$invalid_output" 2>&1; then
  fail "bar rejects an invalid action"
fi
grep -Fx 'Usage: omarchy-toggle-bar [toggle|on|off]' "$invalid_output" >/dev/null ||
  fail "bar invalid action prints usage" "$(cat "$invalid_output")"
[[ ! -f $bar_flag ]] || fail "bar invalid action preserves state"
pass "bar rejects an invalid action without changing state"

ipc_calls=$(wc -l <"$ipc_log")
(( ipc_calls == 6 )) || fail "bar syncs hidden state after each successful action" "IPC calls: $ipc_calls"
if grep -Fvx -- '-q omarchy.bar syncHidden' "$ipc_log" >/dev/null; then
  fail "bar sends the expected hidden-state IPC call" "$(cat "$ipc_log")"
fi
pass "bar syncs hidden state after each successful action"

cat >"$stub_bin/omarchy-toggle" <<'SH'
#!/bin/bash

exit 1
SH
chmod +x "$stub_bin/omarchy-toggle"
if HOME="$test_home" omarchy-toggle-bar off >/dev/null 2>&1; then
  fail "bar propagates a failed state change"
fi
ipc_calls=$(wc -l <"$ipc_log")
(( ipc_calls == 6 )) || fail "bar skips hidden-state sync after a failed state change" "IPC calls: $ipc_calls"
pass "bar propagates a failed state change without syncing"
