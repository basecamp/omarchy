#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$stub_bin" "$test_home"

cat >"$stub_bin/omarchy-migrate-user" <<'SH'
#!/bin/bash
if [[ ${1:-} == "--pending" && ${OMARCHY_TEST_PENDING_MIGRATIONS:-0} == 1 ]]; then
  echo 200-user.sh
  exit 0
else
  exit 1
fi
SH
chmod +x "$stub_bin/omarchy-migrate-user"

cat >"$stub_bin/systemd-run" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$stub_bin/systemd-run"

run_notify() {
  HOME="$test_home" \
  PATH="$stub_bin:$ROOT/bin:$PATH" \
  OMARCHY_TEST_PENDING_MIGRATIONS="$1" \
    "$ROOT/bin/omarchy-migrate-notify"
}

run_notify 0 >"$test_tmp/not-pending.out" 2>"$test_tmp/not-pending.err"
[[ ! -s $test_tmp/not-pending.out ]] || fail "migration notifier stays quiet on stdout without pending migrations"
[[ ! -s $test_tmp/not-pending.err ]] || fail "migration notifier stays quiet on stderr without pending migrations"
pass "migration notifier ignores users with no pending migrations"

run_notify 1 >"$test_tmp/pending.out" 2>"$test_tmp/pending.err"
grep -q 'Omarchy has pending user migrations' "$test_tmp/pending.err" || fail "migration notifier explains pending migrations without notification system"
grep -q 'user/200-user.sh' "$test_tmp/pending.err" || fail "migration notifier lists pending migration names"
pass "migration notifier reports pending user migrations"
