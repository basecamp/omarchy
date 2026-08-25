#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
test_bin="$test_tmp/bin"
calls="$test_tmp/calls"
mkdir -p "$test_bin"
trap 'rm -rf "$test_tmp"' EXIT

cat >"$test_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'package:%s\n' "$*" >>"$OMARCHY_TEST_CALLS"
if [[ ${OMARCHY_TEST_FAIL_STEP:-} == "interrupt" ]]; then
  exit 130
fi
[[ ${OMARCHY_TEST_FAIL_STEP:-} != "package" ]]
SH

cat >"$test_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo:%s\n' "$*" >>"$OMARCHY_TEST_CALLS"
case ${1:-} in
  systemctl) [[ ${OMARCHY_TEST_FAIL_STEP:-} != "service" ]] ;;
  usermod) [[ ${OMARCHY_TEST_FAIL_STEP:-} != "group" ]] ;;
  *) exit 0 ;;
esac
SH

cat >"$test_bin/gum" <<'SH'
#!/bin/bash
printf 'gum:%s\n' "$*" >>"$OMARCHY_TEST_CALLS"
exit 0
SH

cat >"$test_bin/omarchy-system-reboot" <<'SH'
#!/bin/bash
printf 'reboot\n' >>"$OMARCHY_TEST_CALLS"
SH

chmod +x "$test_bin"/*

run_installer() {
  local fail_step="$1"

  : >"$calls"
  set +e
  output=$(PATH="$test_bin:$PATH" \
    OMARCHY_TEST_CALLS="$calls" \
    OMARCHY_TEST_FAIL_STEP="$fail_step" \
    USER="omarchy-test" \
    "$ROOT/bin/omarchy-install-service-nordvpn" 2>&1)
  status=$?
  set -e
}

assert_failed_step() {
  local fail_step="$1"
  local expected_calls="$2"
  local expected_status="${3:-}"

  run_installer "$fail_step"

  (( status != 0 )) || fail "NordVPN installer fails when the $fail_step step fails"
  if [[ -n $expected_status ]]; then
    (( status == expected_status )) || fail "NordVPN installer preserves the $fail_step exit status" "$status"
  fi
  [[ $(<"$calls") == "$expected_calls" ]] ||
    fail "NordVPN installer stops after the $fail_step step fails" "$(<"$calls")"
  [[ $output != *"NordVPN installed!"* ]] ||
    fail "NordVPN installer does not report success after the $fail_step step fails" "$output"
  pass "NordVPN installer stops when the $fail_step step fails"
}

assert_failed_step "package" 'package:nordvpn-bin'
assert_failed_step "interrupt" 'package:nordvpn-bin' 130
assert_failed_step "service" $'package:nordvpn-bin\nsudo:systemctl enable --now nordvpnd'
assert_failed_step "group" $'package:nordvpn-bin\nsudo:systemctl enable --now nordvpnd\nsudo:usermod -aG nordvpn omarchy-test'

run_installer ""
(( status == 0 )) || fail "NordVPN installer succeeds when every required step succeeds" "$output"
expected_success_calls=$'package:nordvpn-bin\nsudo:systemctl enable --now nordvpnd\nsudo:usermod -aG nordvpn omarchy-test\ngum:confirm Reboot now to make NordVPN usable?\nreboot'
[[ $(<"$calls") == "$expected_success_calls" ]] ||
  fail "NordVPN installer runs every setup step before the optional reboot" "$(<"$calls")"
[[ $output == *"NordVPN installed!"* ]] || fail "NordVPN installer reports a successful installation" "$output"
pass "NordVPN installer reports success after every required step succeeds"
