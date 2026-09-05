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

# The helper, with sudo and runuser stubbed at the absolute paths it calls,
# and id stubbed so the test can be the kid, root, or a stranger.
stub_root="$test_tmp/root"
mkdir -p "$stub_root/usr/bin" "$test_tmp/idbin"
export CALLS="$test_tmp/calls" STDIN_SEEN="$test_tmp/stdin"
cat >"$stub_root/usr/bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$CALLS"
cat >"$STDIN_SEEN"
exit "${STUB_SUDO_STATUS:-0}"
SH
cat >"$stub_root/usr/bin/runuser" <<'SH'
#!/bin/bash
printf 'runuser %s\n' "$*" >>"$CALLS"
cat >"$STDIN_SEEN"
exit "${STUB_SUDO_STATUS:-0}"
SH
printf '#!/bin/bash\nexit 0\n' >"$stub_root/usr/bin/true"
cat >"$test_tmp/idbin/id" <<'SH'
#!/bin/bash
# id -u → who runs the helper; id -u NAME → the account's uid.
if [[ $1 == -u && -z ${2:-} ]]; then echo "${STUB_ME:-1000}"; exit 0; fi
case "${2:-}" in
  kid) echo 1000 ;;
  root) echo 0 ;;
  *) echo "id: '${2:-}': no such user" >&2; exit 1 ;;
esac
SH
chmod +x "$stub_root/usr/bin"/* "$test_tmp/idbin/id"
# The helper names /usr/bin/sudo and /usr/bin/runuser outright, so the test runs a copy that names the stubs.
helper="$test_tmp/omarchy-parent-unlock"
sed "s|/usr/bin/sudo|$stub_root/usr/bin/sudo|; s|/usr/bin/true|$stub_root/usr/bin/true|; s|/usr/bin/runuser|$stub_root/usr/bin/runuser|" "$unlock" >"$helper"
chmod +x "$helper"
grep -q '/usr/bin/sudo -k -S -u root -- /usr/bin/true' "$unlock" || fail "the helper asks sudo with -k and -S at absolute paths"
grep -q '/usr/bin/runuser -u "\$user" -- /usr/bin/sudo -k -S -u root' "$unlock" || fail "the helper drops to the account before asking sudo when it runs as root"

run_helper() {
  PATH="$test_tmp/idbin:$PATH" bash "$helper"
}

: >"$CALLS"
printf 's3cret' | PAM_USER=kid PAM_TYPE=auth run_helper || fail "the parent password succeeds"
[[ $(<"$CALLS") == "sudo -k -S -u root -- $stub_root/usr/bin/true" ]] || fail "as the kid, the helper asks sudo to check the password without the cache" "$(<"$CALLS")"
[[ $(<"$STDIN_SEEN") == "s3cret" ]] || fail "the password reaches sudo on stdin" "$(<"$STDIN_SEEN")"
if printf 'wrong' | STUB_SUDO_STATUS=1 PAM_USER=kid PAM_TYPE=auth run_helper 2>/dev/null; then
  fail "a password sudo refuses fails"
fi
: >"$CALLS"
printf 's3cret' | STUB_ME=0 PAM_USER=kid PAM_TYPE=auth run_helper || fail "the parent password succeeds from the login screen, where PAM runs the helper as root"
[[ $(<"$CALLS") == "runuser -u kid -- $stub_root/usr/bin/sudo -k -S -u root -- $stub_root/usr/bin/true" ]] || fail "as root, the helper runs sudo as the kid, never as root" "$(<"$CALLS")"
[[ $(<"$STDIN_SEEN") == "s3cret" ]] || fail "the password still travels on stdin through runuser"
: >"$CALLS"
if printf 's3cret' | STUB_ME=1001 PAM_USER=kid PAM_TYPE=auth run_helper 2>/dev/null; then
  fail "a helper run as neither root nor the account is refused"
fi
if printf 's3cret' | PAM_USER=root PAM_TYPE=auth run_helper 2>/dev/null; then
  fail "the helper refuses to answer for root itself"
fi
if printf 's3cret' | STUB_ME=0 PAM_USER=nobody-here PAM_TYPE=auth run_helper 2>/dev/null; then
  fail "an account id cannot resolve is refused"
fi
if printf '' | PAM_USER=kid PAM_TYPE=auth run_helper 2>/dev/null; then
  fail "an empty password fails"
fi
if printf 's3cret' | PAM_USER=kid PAM_TYPE=account run_helper 2>/dev/null; then
  fail "the helper only answers the auth phase"
fi
[[ ! -s $CALLS ]] || fail "a refused call never reaches sudo or runuser" "$(<"$CALLS")"
pass "omarchy-parent-unlock checks the parent password as the kid, from the lock screen and the login screen, and nothing else"

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
  OMARCHY_INSTALL_USER=kid OMARCHY_PAM_DIR="$pam_dir" PATH="$stub_bin:$PATH" bash "$apply_lock" >/dev/null
}

# The packaged SDDM stack as install/login/sddm.sh leaves it: tabs and all.
packaged_sddm=$'#%PAM-1.0\n\nauth\t\tinclude\t\tsystem-login\naccount\t\tinclude\t\tsystem-login\npassword\tinclude\t\tsystem-login\nsession\t\toptional\tpam_keyinit.so force revoke\nsession\t\tinclude\t\tsystem-login\n-session\toptional\tpam_gnome_keyring.so auto_start'
printf '%s\n' "$packaged_sddm" >"$pam_dir/sddm"

parent_line='auth       [success=1 default=ignore]  pam_exec.so quiet seteuid expose_authtok /usr/bin/omarchy-parent-unlock'

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

# The login screen: SDDM's stack gets the same auth block on a child install,
# built from a kept copy of the packaged file, with every other line intact.
sddm=$(<"$pam_dir/sddm")
[[ $sddm == *$'\n'"$parent_line"$'\n'* ]] || fail "a child install's login screen asks the parent helper" "$sddm"
[[ $sddm == *$'\nauth       required                    pam_shells.so\nauth       requisite                   pam_nologin.so\n'* ]] || fail "the login stack keeps the shells and nologin checks system-login provided"
! grep -qE '^auth[[:space:]]+include[[:space:]]+system-login' "$pam_dir/sddm" || fail "the auth include line is replaced, not kept beside the block"
grep -qE $'^account\t\tinclude\t\tsystem-login$' "$pam_dir/sddm" && grep -qE $'^-session\toptional\tpam_gnome_keyring.so auto_start$' "$pam_dir/sddm" || fail "the account, password, and session lines stay as packaged, tabs and all" "$sddm"
[[ $(<"$pam_dir/sddm.omarchy-orig") == "$packaged_sddm" ]] || fail "the packaged file is kept beside it"
[[ $(grep -c 'omarchy-parent-unlock' "$pam_dir/sddm") == 1 ]] || fail "the helper appears once"
STUB_PROFILE=child run_apply_lock
[[ $(grep -c 'omarchy-parent-unlock' "$pam_dir/sddm") == 1 && $(<"$pam_dir/sddm.omarchy-orig") == "$packaged_sddm" ]] || fail "a rerun rebuilds from the kept copy rather than stacking"
grep -q 'pam_exec.so quiet seteuid expose_authtok' "$pam_dir/omarchy-lock-password" && grep -q 'pam_exec.so quiet seteuid expose_authtok' "$pam_dir/sddm" || fail "both stacks run the helper with seteuid"
pass "a child install's login screen takes the parent password too"

STUB_PROFILE=default run_apply_lock
[[ $(<"$pam_dir/sddm") == "$packaged_sddm" ]] || fail "a run outside the child profile restores the packaged login stack" "$(<"$pam_dir/sddm")"
[[ ! -e $pam_dir/sddm.omarchy-orig ]] || fail "the kept copy goes with it"
pass "the login screen returns to the packaged stack outside the child profile"
