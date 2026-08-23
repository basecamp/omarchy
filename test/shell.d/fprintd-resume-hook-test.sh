#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

hook="$ROOT/default/systemd/system-sleep/fprintd-resume"

# systemd execs the files in system-sleep/ directly, so a hook without the
# executable bit silently never runs. The setup command installs this with
# `cp -p`, which preserves the repo's mode, so the bit has to be set here.
[[ -x $hook ]] ||
  fail "the resume hook is executable" "mode: $(stat -c '%A' "$hook")"
pass "the resume hook is executable"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mock_bin="$tmpdir/bin"
call_log="$tmpdir/systemctl-calls"
mkdir -p "$mock_bin"

cat >"$mock_bin/systemctl" <<SH
#!/bin/bash
printf '%s\n' "\$*" >>"$call_log"
SH
chmod +x "$mock_bin/systemctl"

run_hook() {
  : >"$call_log"
  PATH="$mock_bin:$PATH" "$hook" "$@"
}

# Resume ("post") is the only edge that clears a claim wedged across suspend.
run_hook post suspend
[[ $(<"$call_log") == "try-restart fprintd.service" ]] ||
  fail "resume restarts fprintd to clear a wedged claim" "calls: $(<"$call_log")"
pass "resume restarts fprintd to clear a wedged claim"

# Every resume path lands on "post" regardless of how the machine slept.
run_hook post hibernate
[[ $(<"$call_log") == "try-restart fprintd.service" ]] ||
  fail "resume from hibernate also restarts fprintd" "calls: $(<"$call_log")"
pass "resume from hibernate also restarts fprintd"

# There is nothing to clear before sleep, and try-restart would needlessly
# re-activate a fprintd that idle-exited, so "pre" must do nothing.
run_hook pre suspend
[[ -z $(<"$call_log") ]] ||
  fail "pre-suspend leaves fprintd alone" "calls: $(<"$call_log")"
pass "pre-suspend leaves fprintd alone"
