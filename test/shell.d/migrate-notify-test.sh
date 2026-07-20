#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$stub_bin" "$test_home"

cat >"$stub_bin/omarchy-migrate" <<'SH'
#!/bin/bash
if [[ ${1:-} == "--pending" && ${OMARCHY_TEST_PENDING_MIGRATIONS:-0} == 1 ]]; then
  echo 200-migration.sh
  exit 0
else
  exit 1
fi
SH
chmod +x "$stub_bin/omarchy-migrate"

cat >"$stub_bin/systemd-run" <<'SH'
#!/bin/bash
if [[ ${OMARCHY_TEST_SYSTEMD_RUN:-run} == "fail" ]]; then
  exit 1
fi

command=${!#}
bash -c "$command"
SH
chmod +x "$stub_bin/systemd-run"

cat >"$stub_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$@" >"$OMARCHY_TEST_NOTIFY_ARGS"
SH
chmod +x "$stub_bin/omarchy-notification-send"

run_notify() {
  HOME="$test_home" \
  PATH="$stub_bin:$ROOT/bin:$PATH" \
  OMARCHY_TEST_PENDING_MIGRATIONS="$1" \
  OMARCHY_TEST_NOTIFY_ARGS="$test_tmp/notify-args" \
  OMARCHY_TEST_SYSTEMD_RUN="${2:-run}" \
    "$ROOT/bin/omarchy-migrate-notify"
}

run_notify 0 >"$test_tmp/not-pending.out" 2>"$test_tmp/not-pending.err"
[[ ! -s $test_tmp/not-pending.out ]] || fail "migration notifier stays quiet on stdout without pending migrations"
[[ ! -s $test_tmp/not-pending.err ]] || fail "migration notifier stays quiet on stderr without pending migrations"
pass "migration notifier ignores users with no pending migrations"

run_notify 1 fail >"$test_tmp/pending.out" 2>"$test_tmp/pending.err"
grep -q 'Omarchy has pending migrations' "$test_tmp/pending.err" || fail "migration notifier explains pending migrations without notification system"
grep -q '200-migration.sh' "$test_tmp/pending.err" || fail "migration notifier lists pending migration names"
pass "migration notifier reports pending migrations"

run_notify 1 >"$test_tmp/notified.out" 2>"$test_tmp/notified.err"
grep -Fx 'Pending Omarchy Migrations' "$test_tmp/notify-args" >/dev/null || fail "migration notifier uses pending migrations title"
grep -Fx 'Click to run 1 pending migration.' "$test_tmp/notify-args" >/dev/null || fail "migration notifier describes the pending migration"
grep -Fx '' "$test_tmp/notify-args" >/dev/null || fail "migration notifier includes the large-slot glyph"
pass "migration notifier uses the actionable notification format"
