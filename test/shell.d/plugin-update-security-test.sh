#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
plugins="$test_home/.config/omarchy/plugins"
verify_log="$test_tmp/verify-log"
validate_log="$test_tmp/validate-log"
mkdir -p "$stub_bin" "$plugins"

cat >"$stub_bin/omarchy-default-agent" <<'STUB'
#!/bin/bash
echo codex
STUB
cat >"$stub_bin/omarchy-toggle-enabled" <<'STUB'
#!/bin/bash
[[ $1 == "agent-security-scan" && ${TEST_SCANS:-1} == "1" ]]
STUB
cat >"$stub_bin/omarchy-plugin-verify" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_VERIFY_LOG"
[[ ${TEST_VERIFY_RESULT:-safe} == "safe" ]]
STUB
cat >"$stub_bin/omarchy-plugin-validate" <<'STUB'
#!/bin/bash
printf '%s\n' "$1" >>"$TEST_VALIDATE_LOG"
[[ ${TEST_VALIDATE_RESULT:-valid} == "valid" ]]
STUB
cat >"$stub_bin/omarchy-shell" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$stub_bin"/*

make_plugin() {
  local id="$1"
  local work="$test_tmp/$id-work"
  local bare="$test_tmp/$id.git"
  local installed="$plugins/$id"

  mkdir -p "$work"
  printf '{"schemaVersion":1,"id":"%s","name":"%s","kinds":["service"],"entryPoints":{"service":"Service.qml"}}\n' "$id" "$id" >"$work/manifest.json"
  printf 'import QtQuick\nQtObject {}\n' >"$work/Service.qml"
  git -C "$work" init -q
  git -C "$work" add .
  git -C "$work" -c user.name=Test -c user.email=test@example.com commit -qm Initial
  git clone -q --bare "$work" "$bare"
  git clone -q "$bare" "$installed"
  printf 'import QtQuick\nQtObject { property int version: 2 }\n' >"$work/Service.qml"
  git -C "$work" add .
  git -C "$work" -c user.name=Test -c user.email=test@example.com commit -qm Update
  git -C "$work" push -q "$bare" HEAD
}

make_plugin acme.blocked
make_plugin acme.safe

export HOME="$test_home"
export OMARCHY_PATH="$ROOT"
export PATH="$stub_bin:$ROOT/bin:$PATH"
export TEST_VERIFY_LOG="$verify_log"
export TEST_VALIDATE_LOG="$validate_log"
: >"$verify_log"
: >"$validate_log"

before=$(git -C "$plugins/acme.blocked" rev-parse HEAD)
set +e
TEST_VERIFY_RESULT=blocked omarchy-plugin-update acme.blocked --yes >"$test_tmp/output" 2>&1
status=$?
set -e
(( status != 0 )) || fail "plugin update installs a revision the agent did not clear"
[[ $(git -C "$plugins/acme.blocked" rev-parse HEAD) == "$before" ]] ||
  fail "plugin update changes the installed checkout before clearance"
blocked_revision=$(git -C "$test_tmp/acme.blocked-work" rev-parse HEAD)
grep -qF -- "--revision $blocked_revision" "$verify_log" ||
  fail "plugin update does not review the immutable fetched revision" "$(<"$verify_log")"
grep -qF "Held acme.blocked" "$test_tmp/output" || fail "plugin update does not name a held plugin" "$(<"$test_tmp/output")"
pass "plugin update holds an uncleared revision before changing the checkout"

: >"$verify_log"
TEST_VERIFY_RESULT=safe omarchy-plugin-update acme.safe --yes >/dev/null
[[ $(git -C "$plugins/acme.safe" rev-parse HEAD) == $(git -C "$test_tmp/acme.safe-work" rev-parse HEAD) ]] ||
  fail "plugin update does not install a cleared revision"
[[ $(wc -l <"$verify_log") == 1 ]] || fail "plugin update reviews a changed plugin exactly once"
validation_target=$(head -1 "$validate_log")
[[ $validation_target == /tmp/omarchy-plugin-update-* ]] ||
  fail "plugin update validates the staged candidate before the installed checkout" "$validation_target"
pass "plugin update validates and reviews the candidate before fast-forwarding"

make_plugin acme.explicit
: >"$verify_log"
TEST_VERIFY_RESULT=blocked omarchy-plugin-update acme.explicit --no-verify-with-agent --yes >/dev/null
[[ ! -s $verify_log ]] || fail "plugin update ignores an explicit scan opt-out" "$(<"$verify_log")"
pass "plugin update supports an explicit one-command scan opt-out"

make_plugin acme.dirty
printf 'local edit\n' >>"$plugins/acme.dirty/Service.qml"
: >"$verify_log"
set +e
omarchy-plugin-update acme.dirty --yes >"$test_tmp/dirty-output" 2>&1
status=$?
set -e
(( status != 0 )) || fail "plugin update replaces local source that was not reviewed"
[[ ! -s $verify_log ]] || fail "plugin update spends tokens before rejecting local source drift"
grep -qF "has local changes" "$test_tmp/dirty-output" || fail "plugin update does not explain local source drift"
pass "plugin update rejects local source drift before spending agent tokens"
