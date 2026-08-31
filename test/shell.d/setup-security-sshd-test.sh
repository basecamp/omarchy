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
cat >"$stub_bin/curl" <<'STUB'
#!/bin/bash
printf '%s\n' "${GITHUB_KEYS:?}"
STUB
cat >"$stub_bin/gum" <<'STUB'
#!/bin/bash
case $1 in
choose)
  printf '%s\n' "Import all SSH keys from GitHub"
  ;;
input)
  printf '%s\n' "${GITHUB_USER:-simonallfrey}"
  ;;
confirm)
  printf 'gum %s\n' "$*" >>"${CALL_LOG:?}"
  [[ ${GUM_CONFIRM:-yes} == "yes" ]]
  ;;
*)
  exit 2
  ;;
esac
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
ssh-keygen -q -t ed25519 -N "" -f "$test_dir/second-key"
second_public_key=$(<"$test_dir/second-key.pub")
github_keys="$public_key"$'\n'"$second_public_key"
first_fingerprint=$(ssh-keygen -lf "$test_dir/key.pub" | awk '{ print $2 }')
second_fingerprint=$(ssh-keygen -lf "$test_dir/second-key.pub" | awk '{ print $2 }')

run_setup() {
  local scenario="$1"
  local mode="${2:-key}"
  local home="$test_dir/$scenario/home"
  local root="$test_dir/$scenario/root"
  local -a args

  if [[ $mode == "interactive" ]]; then
    args=()
  elif [[ $mode == "github-flag" ]]; then
    args=(--gh-keys simonallfrey)
  else
    args=(--key="$public_key")
  fi

  mkdir -p "$home" "$root"
  : >"$test_dir/$scenario.calls"

  HOME="$home" USER=tester TEST_ROOT="$root" CALL_LOG="$test_dir/$scenario.calls" \
    GITHUB_KEYS="${GITHUB_KEYS:-}" GUM_CONFIRM="${GUM_CONFIRM:-yes}" \
    SSHD_SYNTAX_VALID="${SSHD_SYNTAX_VALID:-1}" \
    SSHD_PASSWORD_AUTH="${SSHD_PASSWORD_AUTH:-no}" \
    SSHD_KBD_AUTH="${SSHD_KBD_AUTH:-no}" \
    PATH="$stub_bin:$PATH" \
    bash "$ROOT/bin/omarchy-setup-security-sshd" "${args[@]}"
}

output=$(run_setup success)
config="$test_dir/success/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf"
grep -qxF "PasswordAuthentication no" "$config" || fail "SSH setup disables password authentication"
grep -qxF "KbdInteractiveAuthentication no" "$config" || fail "SSH setup disables keyboard-interactive authentication"
grep -qxF "systemctl reload sshd.service" "$test_dir/success.calls" || fail "SSH setup reloads the validated config"
grep -q "Password logins are off" <<<"$output" || fail "SSH setup reports hardening after it succeeds"
pass "SSH setup authorizes a key and disables password logins"

output=$(GITHUB_KEYS="$github_keys" run_setup github-interactive interactive)
authorized_keys="$test_dir/github-interactive/home/.ssh/authorized_keys"
grep -qxF "$public_key" "$authorized_keys" || fail "GitHub setup authorizes the first published key"
grep -qxF "$second_public_key" "$authorized_keys" || fail "GitHub setup authorizes the second published key"
grep -q "GitHub user 'simonallfrey' publishes these SSH keys:" <<<"$output" ||
  fail "GitHub setup identifies the account whose keys will be imported"
grep -qF "$first_fingerprint" <<<"$output" || fail "GitHub setup previews the first key fingerprint"
grep -qF "$second_fingerprint" <<<"$output" || fail "GitHub setup previews the second key fingerprint"
grep -q "Importing all 2 keys lets anyone holding a matching private key log in" <<<"$output" ||
  fail "GitHub setup explains that every fetched key grants login access"
grep -q "to this machine as 'tester' without a password" <<<"$output" ||
  fail "GitHub setup identifies the local account and passwordless access"
grep -qxF "gum confirm --default=false Authorize all displayed GitHub SSH keys?" \
  "$test_dir/github-interactive.calls" || fail "GitHub setup requires a default-no confirmation"
pass "Interactive GitHub setup previews and confirms all published keys"

if GITHUB_KEYS="$github_keys" GUM_CONFIRM=no run_setup github-cancel interactive \
  >"$test_dir/github-cancel.output" 2>&1; then
  fail "GitHub setup must stop when key authorization is declined"
fi
[[ ! -e $test_dir/github-cancel/home/.ssh/authorized_keys ]] ||
  fail "Declining GitHub key authorization must not write authorized_keys"
grep -q "GitHub key import cancelled" "$test_dir/github-cancel.output" ||
  fail "GitHub setup reports that the import was cancelled"
pass "Interactive GitHub setup leaves authorized_keys untouched when declined"

output=$(GITHUB_KEYS="$github_keys" run_setup github-flag github-flag)
grep -q "Importing all 2 keys lets anyone holding a matching private key log in" <<<"$output" ||
  fail "Noninteractive GitHub setup explains that every fetched key grants login access"
! grep -q '^gum confirm ' "$test_dir/github-flag.calls" ||
  fail "The explicit --gh-keys flag must remain noninteractive"
pass "Noninteractive GitHub setup discloses the import without prompting"

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
