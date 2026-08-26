#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
conf_file="$test_tmp/omarchy.conf"
status_script="$test_tmp/omarchy-dev-status"
configured="$test_tmp/checkout"
mismatched="$test_tmp/other-checkout"
mkdir -p "$stub_bin" "$configured" "$mismatched"

# Test a copy so the fixture controls /etc/omarchy.conf without changing the
# public command or touching the host.
sed "s#/etc/omarchy.conf#$conf_file#g" "$ROOT/bin/omarchy-dev-status" >"$status_script"
chmod +x "$status_script"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$stub_bin/sudo"

cat >"$stub_bin/systemctl" <<'SH'
#!/bin/bash

[[ $1 == "--user" && $2 == "show-environment" ]] || exit 2

case "$DEV_STATUS_MANAGER_PATH" in
  '<missing>') printf 'DISPLAY=:0\n' ;;
  '<unavailable>') exit 1 ;;
  *) printf 'OMARCHY_PATH=%s\n' "$DEV_STATUS_MANAGER_PATH" ;;
esac
SH
chmod +x "$stub_bin/systemctl"

printf 'export OMARCHY_PATH="%s"\n' "$configured" >"$conf_file"

run_status() {
  local manager_path="$1" shell_path="$2"

  if [[ $shell_path == "<unset>" ]]; then
    DEV_STATUS_MANAGER_PATH="$manager_path" env -u OMARCHY_PATH \
      PATH="$stub_bin:$PATH" "$status_script"
  else
    DEV_STATUS_MANAGER_PATH="$manager_path" OMARCHY_PATH="$shell_path" \
      PATH="$stub_bin:$PATH" "$status_script"
  fi
}

matching_output=$(run_status "$configured" "$configured")
grep -F 'status: active in this session' <<<"$matching_output" >/dev/null ||
  fail "dev status trusts a matching user-manager session" "$matching_output"
! grep -F 'reboot required' <<<"$matching_output" >/dev/null ||
  fail "dev status does not request a reboot when the user manager matches" "$matching_output"
pass "dev status reports a matching session as active"

mismatch_output=$(run_status "$mismatched" "$configured")
grep -F 'status: reboot required before all session layers use this checkout' <<<"$mismatch_output" >/dev/null ||
  fail "dev status trusts a mismatched user-manager session" "$mismatch_output"
grep -F 'the running session does not match' <<<"$mismatch_output" >/dev/null ||
  fail "dev status explains a real session mismatch" "$mismatch_output"
! grep -F 'status: active in this session' <<<"$mismatch_output" >/dev/null ||
  fail "dev status does not call a mismatched session active" "$mismatch_output"
pass "dev status reports a real session mismatch"

unset_output=$(run_status '<missing>' '<unset>')
grep -F 'current shell:       OMARCHY_PATH=<unset>' <<<"$unset_output" >/dev/null ||
  fail "dev status shows an unset shell path" "$unset_output"
! grep -F 'reboot required' <<<"$unset_output" >/dev/null ||
  fail "dev status does not request a reboot from an outside-session shell" "$unset_output"
! grep -F 'status: active in this session' <<<"$unset_output" >/dev/null ||
  fail "dev status does not call an outside-session shell active" "$unset_output"
grep -F 'status: unknown from this shell' <<<"$unset_output" >/dev/null ||
  fail "dev status marks the session state unknown outside the session" "$unset_output"
grep -F 'normal under sudo or outside the desktop session' <<<"$unset_output" >/dev/null ||
  fail "dev status identifies a sudo or outside-session shell" "$unset_output"
! grep -F 'the running session does not match' <<<"$unset_output" >/dev/null ||
  fail "dev status does not mistake an outside shell for the desktop session" "$unset_output"
pass "dev status identifies an outside-session shell"

unavailable_output=$(run_status '<unavailable>' "$configured")
grep -F 'status: unknown from this shell' <<<"$unavailable_output" >/dev/null ||
  fail "dev status keeps an unavailable user-manager environment unknown" "$unavailable_output"
! grep -F 'reboot required' <<<"$unavailable_output" >/dev/null ||
  fail "dev status does not infer a reboot from the current shell" "$unavailable_output"
! grep -F 'status: active in this session' <<<"$unavailable_output" >/dev/null ||
  fail "dev status does not infer an active session from the current shell" "$unavailable_output"
pass "dev status keeps an unavailable user-manager environment unknown"

printf 'export OMARCHY_PATH="/usr/share/omarchy"\n' >"$conf_file"
inactive_output=$(run_status '<missing>' '<unset>')
grep -F 'dev-link: inactive' <<<"$inactive_output" >/dev/null ||
  fail "dev status preserves inactive default mode" "$inactive_output"
! grep -F 'status:' <<<"$inactive_output" >/dev/null ||
  fail "dev status does not invent a session state in inactive mode" "$inactive_output"
! grep -F 'Note:' <<<"$inactive_output" >/dev/null ||
  fail "dev status keeps inactive default mode quiet" "$inactive_output"
pass "dev status preserves inactive default mode"
