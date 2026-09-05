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

cat >"$mock_bin/setsid" <<'SH'
#!/bin/bash
shift
printf 'launch:%s\n' "$*" >"$OMARCHY_TEST_LOG"
SH

cat >"$mock_bin/omarchy-launch-floating-terminal-with-presentation" <<'SH'
#!/bin/bash
printf 'install:%s\n' "$*" >"$OMARCHY_TEST_LOG"
SH

chmod +x "$mock_bin"/*

launch_log="$test_tmp/launch-log"
PATH="$mock_bin:$PATH" OMARCHY_TEST_INSTALLED=true OMARCHY_TEST_LOG="$launch_log" \
  bash "$ROOT/bin/omarchy-launch-1password"
grep -Fxq 'launch:-- env GSETTINGS_BACKEND=memory 1password' "$launch_log" ||
  fail "1Password launcher starts the installed app with default gsettings"
pass "1Password launcher starts the installed app with default gsettings"

PATH="$mock_bin:$PATH" OMARCHY_TEST_INSTALLED=false OMARCHY_TEST_LOG="$launch_log" \
  bash "$ROOT/bin/omarchy-launch-1password"
grep -Fxq 'install:omarchy-install-service-1password' "$launch_log" ||
  fail "1Password launcher starts the installer when missing"
pass "1Password launcher starts the installer when missing"

grep -Fq '{ omarchy = "1password" }' "$ROOT/default/hypr/bindings/applications.lua" ||
  fail "1Password keybinding uses the conditional launcher"
pass "1Password keybinding uses the conditional launcher"

grep -Fq 'Environment=GSETTINGS_BACKEND=memory' \
  "$ROOT/etc/systemd/user/app-1password@autostart.service.d/text-scaling.conf" ||
  fail "1Password autostart drop-in serves default gsettings"
pass "1Password autostart drop-in serves default gsettings"

grep -Eq '^Exec=env GSETTINGS_BACKEND=memory ' "$ROOT/default/applications/1password.desktop" ||
  fail "1Password desktop override serves default gsettings"
pass "1Password desktop override serves default gsettings"
