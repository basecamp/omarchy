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

printf 'export OMARCHY_PATH="%s"\n' "$configured" >"$conf_file"

run_status() {
  local shell_path="$1"

  if [[ $shell_path == "<unset>" ]]; then
    env -u OMARCHY_PATH PATH="$stub_bin:$PATH" "$status_script"
  else
    OMARCHY_PATH="$shell_path" PATH="$stub_bin:$PATH" "$status_script"
  fi
}

matching_output=$(run_status "$configured")
grep -F 'status: active in this session' <<<"$matching_output" >/dev/null ||
  fail "dev status reports a configured checkout active in the session" "$matching_output"
! grep -F 'reboot required' <<<"$matching_output" >/dev/null ||
  fail "dev status does not request a reboot when the session matches" "$matching_output"
pass "dev status reports a matching session as active"

mismatch_output=$(run_status "$mismatched")
grep -F 'status: reboot required before all session layers use this checkout' <<<"$mismatch_output" >/dev/null ||
  fail "dev status requests a reboot for a real session mismatch" "$mismatch_output"
grep -F 'the running session does not match' <<<"$mismatch_output" >/dev/null ||
  fail "dev status explains a real session mismatch" "$mismatch_output"
! grep -F 'status: active in this session' <<<"$mismatch_output" >/dev/null ||
  fail "dev status does not call a mismatched session active" "$mismatch_output"
pass "dev status reports a real session mismatch"

unset_output=$(run_status '<unset>')
grep -F 'current shell:       OMARCHY_PATH=<unset>' <<<"$unset_output" >/dev/null ||
  fail "dev status shows an unset shell path" "$unset_output"
grep -F 'normal under sudo or outside the desktop session' <<<"$unset_output" >/dev/null ||
  fail "dev status identifies a sudo or outside-session shell" "$unset_output"
! grep -F 'the running session does not match' <<<"$unset_output" >/dev/null ||
  fail "dev status does not mistake an outside shell for the desktop session" "$unset_output"
pass "dev status identifies an outside-session shell"
