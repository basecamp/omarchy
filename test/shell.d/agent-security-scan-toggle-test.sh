#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
notification_log="$test_tmp/notifications"
mkdir -p "$stub_bin" "$test_home"

cat >"$stub_bin/omarchy-default-agent" <<'STUB'
#!/bin/bash
printf '%s\n' "${TEST_AGENT-codex}"
STUB
cat >"$stub_bin/omarchy-notification-send" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFICATION_LOG"
STUB
chmod +x "$stub_bin"/*

export HOME="$test_home"
export PATH="$stub_bin:$ROOT/bin:$PATH"
export NOTIFICATION_LOG="$notification_log"

omarchy-agent-security-scan on
[[ $(omarchy-agent-security-scan status) == "enabled" ]] || fail "security scan toggle enables"
grep -qF "enabled" "$notification_log" || fail "security scan toggle announces enabling"
pass "security scan toggle enables with a selected default agent"

omarchy-agent-security-scan off
[[ $(omarchy-agent-security-scan status) == "disabled" ]] || fail "security scan toggle disables"
pass "security scan toggle disables"

output=$(TEST_AGENT="" omarchy-agent-security-scan on 2>&1) &&
  fail "security scan toggle enables without a default agent" "$output"
grep -qF "Choose a default coding agent" <<<"$output" ||
  fail "security scan toggle explains its default-agent requirement" "$output"
pass "security scan toggle requires a default agent"
