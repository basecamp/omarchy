#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

script="$ROOT/bin/omarchy-sudo-passwordless"
tmpfiles_file="$ROOT/etc/tmpfiles.d/omarchy-nopasswd-sudo.conf"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
grant="$test_tmp/grant"
calls="$test_tmp/calls"
mkdir -p "$mock_bin"

cat >"$mock_bin/gum" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$mock_bin/systemctl" <<'SH'
#!/bin/bash

printf 'systemctl %s\n' "$*" >>"$TEST_CALLS"
[[ ${1:-} == "is-active" && ${TEST_TIMER_ACTIVE:-false} == "true" ]]
SH

cat >"$mock_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo %s\n' "$*" >>"$TEST_CALLS"

case ${1:-} in
test)
  [[ ${2:-} == "-f" && -f $TEST_GRANT ]]
  ;;
tee)
  /usr/bin/tee "$TEST_GRANT"
  ;;
chmod)
  /usr/bin/chmod "$2" "$TEST_GRANT"
  ;;
systemd-run)
  [[ ${TEST_FAIL_SYSTEMD_RUN:-false} != "true" ]]
  ;;
rm)
  /usr/bin/rm -f -- "$TEST_GRANT"
  ;;
systemctl)
  exit 0
  ;;
*)
  echo "unexpected sudo command: $*" >&2
  exit 90
  ;;
esac
SH

chmod +x "$mock_bin/gum" "$mock_bin/sudo" "$mock_bin/systemctl"

run_command() {
  TEST_CALLS="$calls" TEST_GRANT="$grant" PATH="$mock_bin:$PATH" USER=alice \
    "$script" "$@"
}

: >"$calls"
enable_output=$(run_command 15)
[[ -f $grant ]] || fail "successful timer setup leaves the passwordless sudo grant enabled"
[[ $(cat "$grant") == "alice ALL=(ALL) NOPASSWD: ALL" ]] ||
  fail "the enabled grant belongs to the current user" "$(cat "$grant")"
grep -q '^sudo systemd-run --on-active=15m .* rm -f -- /etc/sudoers.d/99-omarchy-nopasswd-alice$' "$calls" ||
  fail "enabling arms the expiry timer" "$(cat "$calls")"
[[ $enable_output == *"automatically disable in 15 minutes"* ]] ||
  fail "success is reported after the timer is armed" "$enable_output"
pass "enabling arms expiry before reporting success"

: >"$calls"
rm -f "$grant"
if failure_output=$(TEST_FAIL_SYSTEMD_RUN=true run_command 15 2>&1); then
  fail "enabling fails when the expiry timer cannot be armed"
fi
[[ ! -e $grant ]] || fail "timer setup failure revokes the new passwordless sudo grant"
[[ $failure_output == *"Revoking access now"* ]] ||
  fail "timer setup failure explains the fail-closed revocation" "$failure_output"
[[ $failure_output != *"Passwordless sudo has been ENABLED"* ]] ||
  fail "timer setup failure does not report that passwordless sudo was enabled" "$failure_output"
pass "timer setup failure revokes a new grant"

: >"$calls"
printf 'alice ALL=(ALL) NOPASSWD: ALL\n' >"$grant"
if update_output=$(TEST_TIMER_ACTIVE=true TEST_FAIL_SYSTEMD_RUN=true run_command 30 2>&1); then
  fail "updating fails when the replacement expiry timer cannot be armed"
fi
[[ ! -e $grant ]] || fail "timer update failure revokes the existing passwordless sudo grant"
[[ $update_output != *"timer updated"* ]] ||
  fail "timer update failure does not report success" "$update_output"
pass "timer update failure revokes the existing grant"

mapfile -t tmpfiles_rules < <(grep -vE '^[[:space:]]*(#|$)' "$tmpfiles_file")
(( ${#tmpfiles_rules[@]} == 1 )) ||
  fail "passwordless sudo ships one tmpfiles rule" "${tmpfiles_rules[*]}"

fake_root="$test_tmp/root"
sudoers_dir="$fake_root/etc/sudoers.d"
mkdir -p "$sudoers_dir"
grant_names=(alice buildbot-2 user.123 'service$')
for grant_name in "${grant_names[@]}"; do
  touch "$sudoers_dir/99-omarchy-nopasswd-$grant_name"
done
touch "$sudoers_dir/omarchy-dns"

systemd-tmpfiles --root="$fake_root" --remove --inline "${tmpfiles_rules[@]}"
[[ -f $sudoers_dir/99-omarchy-nopasswd-alice ]] ||
  fail "boot-only cleanup leaves a live grant alone outside boot"

systemd-tmpfiles --root="$fake_root" --remove --boot --inline "${tmpfiles_rules[@]}"
for grant_name in "${grant_names[@]}"; do
  stale_grant="$sudoers_dir/99-omarchy-nopasswd-$grant_name"
  [[ ! -e $stale_grant ]] || fail "boot cleanup removes every generated grant" "$stale_grant"
done
[[ -f $sudoers_dir/omarchy-dns ]] || fail "boot cleanup preserves unrelated sudoers rules"
pass "systemd-tmpfiles removes generated grants only during boot"
