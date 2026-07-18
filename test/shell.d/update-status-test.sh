#!/bin/bash

set -euo pipefail

# shellcheck source=test/shell.d/base-test.sh
source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/checkupdates" <<'SH'
#!/bin/bash

case "${TEST_CHECKUPDATES:-updates}" in
  updates)
    printf 'linux 6.10.1-1 -> 6.10.2-1\nomarchy 4.0.0-1 -> 4.0.1-1\n'
    exit 0
    ;;
  none)
    exit 2
    ;;
  empty-success)
    exit 0
    ;;
  rows-with-current-exit)
    printf 'linux 1.0-1 -> 1.0-2\n'
    exit 2
    ;;
  fail)
    printf 'temporary database failure\n' >&2
    exit 1
    ;;
  malformed)
    printf 'linux 6.10.1-1 -> 6.10.2-1\nnot a package update row\n'
    exit 0
    ;;
  duplicate)
    printf 'linux 6.10.1-1 -> 6.10.2-1\nlinux 6.10.1-1 -> 6.10.3-1\n'
    exit 0
    ;;
  timeout)
    sleep 5
    exit 0
    ;;
esac
SH
chmod +x "$stub_bin/checkupdates"

run_status() {
  PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-update-status"
}

status=$(TEST_CHECKUPDATES=updates run_status)
jq -e '
  .schemaVersion == 1 and
  .available == true and
  .state == "updates" and
  .reason == "" and
  .count == 2 and
  .packages == [
    {"name":"linux","installed":"6.10.1-1","target":"6.10.2-1"},
    {"name":"omarchy","installed":"4.0.0-1","target":"4.0.1-1"}
  ]
' <<<"$status" >/dev/null
pass "structured package status preserves all repository updates"

status=$(TEST_CHECKUPDATES=none run_status)
jq -e '.available == true and .state == "current" and .count == 0 and .packages == []' <<<"$status" >/dev/null
pass "structured package status distinguishes no updates"

status=$(TEST_CHECKUPDATES=empty-success run_status)
jq -e '.state == "invalid" and .reason == "inconsistent-checkupdates-output" and .packages == []' <<<"$status" >/dev/null
pass "structured package status rejects empty success output"

status=$(TEST_CHECKUPDATES=rows-with-current-exit run_status)
jq -e '.state == "invalid" and .reason == "inconsistent-checkupdates-output" and .packages == []' <<<"$status" >/dev/null
pass "structured package status rejects rows with the no-updates exit code"

status=$(TEST_CHECKUPDATES=fail run_status)
jq -e '.available == false and .state == "unavailable" and .reason == "checkupdates-failed" and .packages == []' <<<"$status" >/dev/null
pass "structured package status reports checker failure without stale rows"

status=$(TEST_CHECKUPDATES=malformed run_status)
jq -e '.available == true and .state == "invalid" and .reason == "malformed-checkupdates-output" and .packages == []' <<<"$status" >/dev/null
pass "structured package status fails closed on malformed output"

status=$(TEST_CHECKUPDATES=duplicate run_status)
jq -e '.state == "invalid" and .packages == []' <<<"$status" >/dev/null
pass "structured package status rejects duplicate package rows"

status=$(TEST_CHECKUPDATES=timeout OMARCHY_UPDATE_STATUS_TIMEOUT=1 run_status)
jq -e '.available == false and .state == "unavailable" and .reason == "checkupdates-timeout" and .packages == []' <<<"$status" >/dev/null
pass "structured package status bounds a stalled package check"

minimal_bin="$test_tmp/minimal-bin"
mkdir -p "$minimal_bin"
for command in date dirname jq mktemp rm; do
  ln -s "$(command -v "$command")" "$minimal_bin/$command"
done
ln -s "$ROOT/bin/omarchy-cmd-missing" "$minimal_bin/omarchy-cmd-missing"

status=$(PATH="$minimal_bin" "$ROOT/bin/omarchy-update-status")
jq -e '.available == false and .state == "unavailable" and .reason == "missing-checkupdates"' <<<"$status" >/dev/null
pass "structured package status reports a missing checker explicitly"
