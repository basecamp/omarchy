#!/bin/bash
#
# Verifies the privilege posture of a child install (Omarchy's kids mode): the
# kid account is outside wheel and holds an explicit sudo grant, sudo asks for
# the parent password and refuses the kid's, polkit's admin identity is root,
# and the one passwordless action left to the kid is the browser accent write.
#
# Runs only on a child install, and only with both passwords supplied: the
# harness (omarchy-iso-test --child) sets OMARCHY_ACCEPTANCE_SUDO_PASSWORD to
# the parent password and OMARCHY_ACCEPTANCE_USER_PASSWORD to the kid's.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

if ! omarchy-profile-child; then
  pass "child install checks skipped: not a child install"
  exit 0
fi

if [[ -z ${OMARCHY_ACCEPTANCE_SUDO_PASSWORD:-} || -z ${OMARCHY_ACCEPTANCE_USER_PASSWORD:-} ]]; then
  pass "child install checks skipped: set OMARCHY_ACCEPTANCE_SUDO_PASSWORD (parent) and OMARCHY_ACCEPTANCE_USER_PASSWORD (kid) to run them"
  exit 0
fi

# Start from no cached credential, so each probe below proves its own password.
sudo -K

if id -nG | grep -qw wheel; then
  fail "the kid account is outside wheel" "groups: $(id -nG)"
fi
pass "the kid account is outside wheel"

if printf '%s\n' "$OMARCHY_ACCEPTANCE_USER_PASSWORD" | sudo -S -k -v 2>/dev/null; then
  fail "sudo refuses the kid password"
fi
pass "sudo refuses the kid password"

printf '%s\n' "$OMARCHY_ACCEPTANCE_SUDO_PASSWORD" | sudo -S -k -v 2>/dev/null ||
  fail "sudo accepts the parent password"
pass "sudo accepts the parent password"

sudo -n grep -qx 'Defaults rootpw' /etc/sudoers.d/omarchy-parent ||
  fail "sudo is configured to ask for root's password"
sudo -n test -f "/etc/sudoers.d/omarchy-parent-$USER" ||
  fail "the kid account holds its own sudo grant"
grep -q 'return \["unix-user:root"\]' /etc/polkit-1/rules.d/40-omarchy-parent.rules ||
  fail "polkit authenticates administrative prompts as root"
pass "sudo and polkit are pointed at the parent password"

# The long listing prints the matched entry's tags: !authenticate marks the
# one passwordless action the kid keeps, and its absence on the DNS switch
# shows that grant no longer reaches the account.
sudo -n -l -l /usr/bin/omarchy-theme-set-browser-policy 000000 2>/dev/null | grep -q '!authenticate' ||
  fail "the kid keeps the browser accent write passwordless"
if sudo -n -l -l /usr/bin/omarchy-dns Cloudflare 2>/dev/null | grep -q '!authenticate'; then
  fail "the DNS switch is no longer passwordless for the kid"
fi
pass "only the browser accent write stays passwordless for the kid"

[[ $(cat /etc/omarchy/profile) == "child" ]] || fail "the install profile marker records a child install"
pass "the install profile marker records a child install"

# The parent password opens the lock screen and the login screen: both PAM
# stacks carry the helper after the kid's own password, run with seteuid, and
# SDDM's packaged file is kept beside it. The harness proves the login itself
# by typing the parent password at SDDM on a child run.
helper='pam_exec.so quiet seteuid expose_authtok /usr/bin/omarchy-parent-unlock'
sudo -n grep -qF "$helper" /etc/pam.d/omarchy-lock-password || fail "the lock screen's stack hands the parent password to omarchy-parent-unlock"
sudo -n grep -qF "$helper" /etc/pam.d/sddm || fail "the login screen's stack hands the parent password to omarchy-parent-unlock"
sudo -n grep -qE '^auth[[:space:]]+\[success=2 default=ignore\][[:space:]]+pam_unix\.so' /etc/pam.d/sddm || fail "the login screen tries the kid's password first"
sudo -n test -f /etc/pam.d/sddm.omarchy-orig || fail "the packaged login stack is kept beside the child one"
sudo -n grep -qE '^auth[[:space:]]+requisite[[:space:]]+pam_nologin\.so' /etc/pam.d/sddm || fail "the login stack keeps the nologin check"
pass "the parent password is wired into the lock screen and the login screen"

sudo -K
