#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
[[ ${OMARCHY_TEST_INSTALLED:-false} == "true" ]]
SH

cat >"$mock_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$mock_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
:
SH

cat >"$mock_bin/setsid" <<'SH'
#!/bin/bash
printf 'launch:%s\n' "$*" >"$OMARCHY_TEST_LOG"
SH

cat >"$mock_bin/uwsm-app" <<'SH'
#!/bin/bash
printf 'direct:%s\n' "$*" >"$OMARCHY_TEST_LOG"
SH

cat >"$mock_bin/omarchy-launch-floating-terminal-with-presentation" <<'SH'
#!/bin/bash
printf 'install:%s\n' "$*" >"$OMARCHY_TEST_LOG"
SH

chmod +x "$mock_bin"/*

launch_log="$test_tmp/launch-log"
PATH="$mock_bin:$PATH" OMARCHY_TEST_INSTALLED=true OMARCHY_TEST_LOG="$launch_log" \
  bash "$ROOT/bin/omarchy-launch-1password"
grep -Fxq 'launch:uwsm-app -- 1password' "$launch_log" || fail "1Password launcher starts the installed app"
pass "1Password launcher starts the installed app"

PATH="$mock_bin:$PATH" OMARCHY_TEST_INSTALLED=false OMARCHY_TEST_LOG="$launch_log" \
  bash "$ROOT/bin/omarchy-launch-1password"
grep -Fxq 'install:omarchy-install-service-1password' "$launch_log" ||
  fail "1Password launcher starts the installer when missing"
pass "1Password launcher starts the installer when missing"

: >"$launch_log"
PATH="$mock_bin:$PATH" OMARCHY_TEST_LOG="$launch_log" \
  bash "$ROOT/bin/omarchy-install-service-1password"
for _ in {1..50}; do
  [[ -s $launch_log ]] && break
  sleep 0.01
done
grep -Fxq 'launch:uwsm-app -- 1password' "$launch_log" ||
  fail "1Password installer detaches the app from its terminal" "$(cat "$launch_log")"
pass "1Password installer detaches the app from its terminal"

grep -Fq '{ omarchy = "1password" }' "$ROOT/default/hypr/bindings/applications.lua" ||
  fail "1Password keybinding uses the conditional launcher"
pass "1Password keybinding uses the conditional launcher"
