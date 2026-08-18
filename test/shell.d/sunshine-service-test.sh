#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

installer="$ROOT/bin/omarchy-install-service-sunshine"
remover="$ROOT/bin/omarchy-remove-service-sunshine"
migration="$ROOT/migrations/1786961462.sh"
sunshine_service="app-dev.lizardbyte.app.Sunshine.service"
legacy_entry='o.launch_on_start("sunshine")'
legacy_near_match='oxlaunch_on_start("sunshine")'

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
call_log="$test_tmp/calls"
mkdir -p "$mock_bin" "$test_home/.config/hypr"

cat >"$mock_bin/systemctl" <<'SH'
#!/bin/bash
printf 'systemctl:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
[[ ${OMARCHY_TEST_SYSTEMCTL_FAIL:-false} != "true" ]]
SH

cat >"$mock_bin/omarchy-pkg-present" <<'SH'
#!/bin/bash
[[ ${OMARCHY_TEST_SUNSHINE_INSTALLED:-false} == "true" ]]
SH

for command in omarchy-pkg-add omarchy-pkg-drop omarchy-webapp-install omarchy-webapp-remove omarchy-launch-webapp; do
  cat >"$mock_bin/$command" <<'SH'
#!/bin/bash
exit 0
SH
done

cat >"$mock_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$mock_bin"/*

printf '%s\n' 'o.launch_on_start("existing-service")' >"$test_home/.config/hypr/autostart.lua"
PATH="$mock_bin:$PATH" HOME="$test_home" OMARCHY_TEST_LOG="$call_log" bash "$installer"

grep -Fxq "systemctl:--user enable --now $sunshine_service" "$call_log" ||
  fail "Sunshine installer enables the canonical user service"
if grep -Fxq "$legacy_entry" "$test_home/.config/hypr/autostart.lua"; then
  fail "Sunshine installer does not add a second Hyprland startup path"
fi
pass "Sunshine installer uses only the canonical user service"

printf '%s\n' 'o.launch_on_start("existing-service")' "$legacy_near_match" "$legacy_entry" >"$test_home/.config/hypr/autostart.lua"
PATH="$mock_bin:$PATH" HOME="$test_home" OMARCHY_TEST_LOG="$call_log" bash "$remover"

grep -Fxq "systemctl:--user disable --now $sunshine_service" "$call_log" ||
  fail "Sunshine remover disables the canonical user service"
grep -Fxq 'o.launch_on_start("existing-service")' "$test_home/.config/hypr/autostart.lua" ||
  fail "Sunshine remover preserves unrelated Hyprland autostart entries"
grep -Fxq "$legacy_near_match" "$test_home/.config/hypr/autostart.lua" ||
  fail "Sunshine remover only clears the exact legacy Hyprland entry"
if grep -Fxq "$legacy_entry" "$test_home/.config/hypr/autostart.lua"; then
  fail "Sunshine remover clears the legacy Hyprland startup path"
fi
pass "Sunshine remover cleans up both startup mechanisms"

: >"$call_log"
printf '%s\n' 'o.launch_on_start("existing-service")' "$legacy_near_match" "$legacy_entry" >"$test_home/.config/hypr/autostart.lua"
PATH="$mock_bin:$PATH" HOME="$test_home" OMARCHY_TEST_LOG="$call_log" \
  OMARCHY_TEST_SUNSHINE_INSTALLED=true bash -euo pipefail "$migration"

grep -Fxq "systemctl:--user enable $sunshine_service" "$call_log" ||
  fail "Sunshine migration enables the canonical user service for the next login"
if grep -Fq -- '--now' "$call_log"; then
  fail "Sunshine migration does not start a conflicting second server"
fi
grep -Fxq 'o.launch_on_start("existing-service")' "$test_home/.config/hypr/autostart.lua" ||
  fail "Sunshine migration preserves unrelated Hyprland autostart entries"
grep -Fxq "$legacy_near_match" "$test_home/.config/hypr/autostart.lua" ||
  fail "Sunshine migration only clears the exact legacy Hyprland entry"
if grep -Fxq "$legacy_entry" "$test_home/.config/hypr/autostart.lua"; then
  fail "Sunshine migration removes the legacy Hyprland startup path"
fi
pass "Sunshine migration hands autostart to systemd without disrupting the current session"

calls_before=$(wc -l <"$call_log")
PATH="$mock_bin:$PATH" HOME="$test_home" OMARCHY_TEST_LOG="$call_log" \
  OMARCHY_TEST_SUNSHINE_INSTALLED=true bash -euo pipefail "$migration"
calls_after=$(wc -l <"$call_log")
(( calls_before == calls_after )) || fail "Sunshine migration is idempotent"
pass "Sunshine migration is idempotent"

printf '%s\n' "$legacy_entry" >"$test_home/.config/hypr/autostart.lua"
if PATH="$mock_bin:$PATH" HOME="$test_home" OMARCHY_TEST_LOG="$call_log" \
  OMARCHY_TEST_SUNSHINE_INSTALLED=true OMARCHY_TEST_SYSTEMCTL_FAIL=true \
  bash "$migration" >/dev/null 2>&1; then
  fail "Sunshine migration reports a service enable failure"
fi
grep -Fxq "$legacy_entry" "$test_home/.config/hypr/autostart.lua" ||
  fail "Sunshine migration keeps the legacy startup path when service enablement fails"
pass "Sunshine migration keeps its retry state after a service enable failure"

: >"$call_log"
PATH="$mock_bin:$PATH" HOME="$test_home" OMARCHY_TEST_LOG="$call_log" \
  OMARCHY_TEST_SUNSHINE_INSTALLED=false bash -euo pipefail "$migration"
if [[ -s $call_log ]]; then
  fail "Sunshine migration does not enable a service for an uninstalled package"
fi
if grep -Fxq "$legacy_entry" "$test_home/.config/hypr/autostart.lua"; then
  fail "Sunshine migration clears a stale legacy entry after package removal"
fi
pass "Sunshine migration clears stale autostart state after package removal"
