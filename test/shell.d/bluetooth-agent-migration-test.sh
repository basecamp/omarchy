#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1786728635.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"

cat >"$test_tmp/bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'pkg-add %s\n' "$*" >>"$CALL_LOG"
exit "${TEST_PKG_ADD_STATUS:-0}"
SH

cat >"$test_tmp/bin/systemctl" <<'SH'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$CALL_LOG"
exit 0
SH

chmod +x "$test_tmp/bin"/*

call_log="$test_tmp/calls.log"

run_migration() {
  : >"$call_log"
  PATH="$test_tmp/bin:$PATH" CALL_LOG="$call_log" "$@" bash -euo pipefail "$migration"
}

# The agent imports python-dbus. The ISO pacstraps it from the base package
# list, but an existing install only receives it from this migration, and a
# restart before the install would loop on ImportError every two seconds.
run_migration env >/dev/null || fail "the agent migration runs cleanly" "$(cat "$call_log")"
grep -qx 'pkg-add python-dbus' "$call_log" ||
  fail "the agent migration installs python-dbus" "$(cat "$call_log")"
pass "the agent migration installs python-dbus"

install_line=$(grep -n '^pkg-add python-dbus$' "$call_log" | cut -d: -f1)
restart_line=$(grep -n '^systemctl --user restart bt-agent.service$' "$call_log" | cut -d: -f1)
[[ -n $restart_line ]] || fail "the agent migration restarts an enabled bt-agent" "$(cat "$call_log")"
((install_line < restart_line)) ||
  fail "the agent migration installs python-dbus before restarting bt-agent" "$(cat "$call_log")"
pass "the agent migration installs python-dbus before restarting bt-agent"

# A failed install must stop the migration so it stays pending, not restart
# the unit into a crash loop and then mark itself done.
if run_migration env TEST_PKG_ADD_STATUS=1 >/dev/null 2>&1; then
  fail "the agent migration fails when python-dbus cannot be installed" "$(cat "$call_log")"
fi
grep -q 'restart bt-agent.service' "$call_log" &&
  fail "the agent migration does not restart bt-agent without python-dbus" "$(cat "$call_log")"
pass "the agent migration stays pending when python-dbus cannot be installed"
