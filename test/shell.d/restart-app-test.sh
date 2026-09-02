#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/pkill" <<'SH'
#!/bin/bash
printf 'pkill:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
SH

cat >"$mock_bin/systemd-run" <<'SH'
#!/bin/bash
printf 'systemd-run:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
SH

cat >"$mock_bin/uwsm-app" <<'SH'
#!/bin/bash
printf 'uwsm-app:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
SH

cat >"$mock_bin/setsid" <<'SH'
#!/bin/bash
printf 'setsid:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
SH

chmod +x "$mock_bin"/*

export PATH="$mock_bin:$PATH"
export OMARCHY_TEST_LOG="$test_tmp/log"
: >"$OMARCHY_TEST_LOG"

bash "$ROOT/bin/omarchy-restart-app" hyprsunset extra-arg

grep -Fxq 'pkill:-x hyprsunset' "$OMARCHY_TEST_LOG" ||
  fail "restart-app kills the named process" "$(<"$OMARCHY_TEST_LOG")"
pass "restart-app kills the named process"

grep -Fq 'setsid:' "$OMARCHY_TEST_LOG" &&
  fail "restart-app does not launch via setsid in the caller cgroup" "$(<"$OMARCHY_TEST_LOG")"
grep -Fq 'uwsm-app:' "$OMARCHY_TEST_LOG" &&
  fail "restart-app does not invoke uwsm-app in this process" "$(<"$OMARCHY_TEST_LOG")"
pass "restart-app does not launch uwsm-app in the caller cgroup"

systemd_line=$(grep '^systemd-run:' "$OMARCHY_TEST_LOG" || true)
[[ $systemd_line == *'--user '* ]] || fail "restart-app uses the user systemd" "$systemd_line"
[[ $systemd_line == *'--no-block '* ]] || fail "restart-app does not wait for the app" "$systemd_line"
[[ $systemd_line == *'--slice=app-graphical.slice '* ]] ||
  fail "restart-app relaunches into the graphical app slice" "$systemd_line"
[[ $systemd_line == *' -- uwsm-app -- hyprsunset extra-arg' ]] ||
  fail "restart-app hands the command to uwsm-app via systemd-run" "$systemd_line"
pass "restart-app detaches via systemd-run --no-block"

grep -F 'setsid uwsm-app' "$ROOT/bin/omarchy-restart-app" &&
  fail "restart-app source no longer backgrounds uwsm-app with setsid"
pass "restart-app source no longer backgrounds uwsm-app with setsid"
