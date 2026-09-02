#!/bin/bash
#
# On a child install the parent password opens the lock screen too. The stack
# omarchy-apply-lock writes tries the kid's password first and then hands the
# typed password to omarchy-parent-unlock, which asks sudo whether it is
# root's, without touching the credential cache. Both run here against stubs.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

unlock="$ROOT/bin/omarchy-parent-unlock"
apply_lock="$ROOT/bin/omarchy-apply-lock"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

# The helper, with sudo stubbed at the absolute path it calls.
stub_root="$test_tmp/root"
mkdir -p "$stub_root/usr/bin"
export CALLS="$test_tmp/calls" STDIN_SEEN="$test_tmp/stdin"
cat >"$stub_root/usr/bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$CALLS"
cat >"$STDIN_SEEN"
exit "${STUB_SUDO_STATUS:-0}"
SH
printf '#!/bin/bash\nexit 0\n' >"$stub_root/usr/bin/true"
chmod +x "$stub_root/usr/bin"/*
# The helper names /usr/bin/sudo outright, so the test runs a copy that names the stub.
helper="$test_tmp/omarchy-parent-unlock"
sed "s|/usr/bin/sudo|$stub_root/usr/bin/sudo|; s|/usr/bin/true|$stub_root/usr/bin/true|" "$unlock" >"$helper"
chmod +x "$helper"
grep -q '/usr/bin/sudo -k -S -u root -- /usr/bin/true' "$unlock" || fail "the helper asks sudo with -k and -S at absolute paths"

: >"$CALLS"
printf 's3cret' | PAM_USER=kid PAM_TYPE=auth bash "$helper" || fail "the parent password succeeds"
[[ $(<"$CALLS") == "sudo -k -S -u root -- $stub_root/usr/bin/true" ]] || fail "the helper asks sudo to check the password without the cache" "$(<"$CALLS")"
[[ $(<"$STDIN_SEEN") == "s3cret" ]] || fail "the password reaches sudo on stdin" "$(<"$STDIN_SEEN")"
if printf 'wrong' | STUB_SUDO_STATUS=1 PAM_USER=kid PAM_TYPE=auth bash "$helper" 2>/dev/null; then
  fail "a password sudo refuses fails"
fi
: >"$CALLS"
if printf 's3cret' | PAM_USER=root PAM_TYPE=auth bash "$helper" 2>/dev/null; then
  fail "the helper refuses to answer for root itself"
fi
if printf '' | PAM_USER=kid PAM_TYPE=auth bash "$helper" 2>/dev/null; then
  fail "an empty password fails"
fi
if printf 's3cret' | PAM_USER=kid PAM_TYPE=account bash "$helper" 2>/dev/null; then
  fail "the helper only answers the auth phase"
fi
[[ ! -s $CALLS ]] || fail "a refused call never reaches sudo" "$(<"$CALLS")"
pass "omarchy-parent-unlock accepts the parent password through sudo and nothing else"

# The stack omarchy-apply-lock writes, with /etc/pam.d redirected into scratch.
stub_bin="$test_tmp/bin"
pam_dir="$test_tmp/pam.d"
mkdir -p "$stub_bin" "$pam_dir"
cat >"$stub_bin/sudo" <<SH
#!/bin/bash
args=()
for arg in "\$@"; do args+=("\${arg//\/etc\/pam.d/$pam_dir}"); done
exec "\${args[@]}"
SH
cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 1
SH
cat >"$stub_bin/omarchy-shell" <<'SH'
#!/bin/bash
exit 1
SH
cat >"$stub_bin/omarchy-profile-child" <<'SH'
#!/bin/bash
[[ ${STUB_PROFILE:-default} == child ]]
SH
chmod +x "$stub_bin"/*

run_apply_lock() {
  OMARCHY_INSTALL_USER=kid PATH="$stub_bin:$PATH" bash "$apply_lock" >/dev/null
}

parent_line='auth       [success=1 default=ignore]  pam_exec.so quiet expose_authtok /usr/bin/omarchy-parent-unlock'

STUB_PROFILE=default run_apply_lock
! grep -qF 'omarchy-parent-unlock' "$pam_dir/omarchy-lock-password" || fail "a default install's lock screen knows no parent password"
grep -qF 'auth       [success=1 default=bad]     pam_unix.so try_first_pass nullok' "$pam_dir/omarchy-lock-password" || fail "a default install's stack is unchanged"
pass "a default install's lock stack is as it was"

STUB_PROFILE=child run_apply_lock
stack=$(<"$pam_dir/omarchy-lock-password")
[[ $stack == *$'\n'"$parent_line"$'\n'* ]] || fail "a child install's lock stack asks the parent helper" "$stack"
[[ $(sed -n '3,6p' "$pam_dir/omarchy-lock-password") == "-auth      [success=3 default=ignore]  pam_systemd_home.so
auth       [success=2 default=ignore]  pam_unix.so try_first_pass nullok
$parent_line
auth       [default=die]               pam_faillock.so authfail deny=10 unlock_time=120" ]] ||
  fail "the kid's password is tried first, the parent helper second, and either success skips the failure line" "$stack"
[[ $(sed -n '2p' "$pam_dir/omarchy-lock-password") == 'auth       required                    pam_faillock.so preauth silent deny=10 unlock_time=120' ]] || fail "faillock still leads the stack"
grep -qF 'auth       required                    pam_faillock.so authsucc' "$pam_dir/omarchy-lock-password" && grep -qF 'account    include                     system-local-login' "$pam_dir/omarchy-lock-password" || fail "the rest of the stack is as it was"
! grep -qF 'default=bad' "$pam_dir/omarchy-lock-password" || fail "no module marks the stack bad before the parent helper has answered"
pass "a child install's lock screen takes the parent password after the kid's"
