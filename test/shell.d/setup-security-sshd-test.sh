#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

stub_bin="$test_dir/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-pkg-add" <<'STUB'
#!/bin/bash
printf 'pkg %s\n' "$*" >>"${CALL_LOG:?}"
STUB
cat >"$stub_bin/omarchy-cmd-missing" <<'STUB'
#!/bin/bash
exit 0
STUB
cat >"$stub_bin/systemctl" <<'STUB'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"${CALL_LOG:?}"
STUB
cat >"$stub_bin/sshd" <<'STUB'
#!/bin/bash
case $1 in
-t)
  [[ ${SSHD_SYNTAX_VALID:-1} == 1 ]]
  ;;
-T)
  # OpenSSH 10.x dumps keywords in CamelCase; 9.x dumped them lowercase.
  if [[ ${SSHD_DUMP_LOWERCASE:-0} == 1 ]]; then
    printf 'passwordauthentication %s\n' "${SSHD_PASSWORD_AUTH:-no}"
    printf 'kbdinteractiveauthentication %s\n' "${SSHD_KBD_AUTH:-no}"
  else
    printf 'PasswordAuthentication %s\n' "${SSHD_PASSWORD_AUTH:-no}"
    printf 'KbdInteractiveAuthentication %s\n' "${SSHD_KBD_AUTH:-no}"
  fi
  ;;
*)
  exit 2
  ;;
esac
STUB
cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
case $1 in
install)
  destination="${TEST_ROOT:?}${4:?}"
  /usr/bin/mkdir -p "${destination%/*}"
  /usr/bin/install -Dm644 /dev/stdin "$destination"
  ;;
rm)
  /usr/bin/rm -f "${TEST_ROOT:?}${3:?}"
  ;;
*)
  exec "$@"
  ;;
esac
STUB
chmod +x "$stub_bin"/*

ssh-keygen -q -t ed25519 -N "" -f "$test_dir/key"
public_key=$(<"$test_dir/key.pub")

run_setup() {
  local scenario="$1"
  local home="$test_dir/$scenario/home"
  local root="$test_dir/$scenario/root"

  mkdir -p "$home" "$root"
  : >"$test_dir/$scenario.calls"

  HOME="$home" TEST_ROOT="$root" CALL_LOG="$test_dir/$scenario.calls" \
    SSHD_SYNTAX_VALID="${SSHD_SYNTAX_VALID:-1}" \
    SSHD_PASSWORD_AUTH="${SSHD_PASSWORD_AUTH:-no}" \
    SSHD_KBD_AUTH="${SSHD_KBD_AUTH:-no}" \
    PATH="$stub_bin:$PATH" \
    bash "$ROOT/bin/omarchy-setup-security-sshd" --key="$public_key"
}

output=$(run_setup success)
config="$test_dir/success/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf"
grep -qxF "PasswordAuthentication no" "$config" || fail "SSH setup disables password authentication"
grep -qxF "KbdInteractiveAuthentication no" "$config" || fail "SSH setup disables keyboard-interactive authentication"
grep -qxF "systemctl reload sshd.service" "$test_dir/success.calls" || fail "SSH setup reloads the validated config"
grep -q "Password logins are off" <<<"$output" || fail "SSH setup reports hardening after it succeeds"
pass "SSH setup authorizes a key and disables password logins"

output=$(SSHD_DUMP_LOWERCASE=1 run_setup success-legacy)
config="$test_dir/success-legacy/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf"
[[ -e $config ]] || fail "SSH setup accepts the lowercase sshd -T dump of OpenSSH 9.x"
grep -q "Password logins are off" <<<"$output" || fail "SSH setup reports hardening on OpenSSH 9.x"
pass "SSH setup verifies settings across sshd -T keyword casings"

if SSHD_PASSWORD_AUTH=yes run_setup ineffective >"$test_dir/ineffective.output" 2>&1; then
  fail "SSH setup must fail when password authentication remains effective"
fi
[[ ! -e $test_dir/ineffective/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] ||
  fail "SSH setup removes an ineffective hardening config"
! grep -qF "systemctl reload sshd.service" "$test_dir/ineffective.calls" ||
  fail "SSH setup must not reload ineffective hardening"
! grep -q "Password logins are off" "$test_dir/ineffective.output" ||
  fail "SSH setup must not claim ineffective hardening succeeded"
pass "SSH setup verifies the effective daemon settings"

if SSHD_SYNTAX_VALID=0 run_setup invalid >"$test_dir/invalid.output" 2>&1; then
  fail "SSH setup must fail when sshd rejects its config"
fi
[[ ! -e $test_dir/invalid/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] ||
  fail "SSH setup removes a rejected hardening config"
! grep -qF "systemctl reload sshd.service" "$test_dir/invalid.calls" ||
  fail "SSH setup must not reload a rejected config"
! grep -q "Password logins are off" "$test_dir/invalid.output" ||
  fail "SSH setup must not claim rejected hardening succeeded"
pass "SSH setup fails safely when sshd rejects the config"
