#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

migration="$ROOT/migrations/1788124236.sh"
stub_bin="$test_dir/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/systemctl" <<'STUB'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"${CALL_LOG:?}"
case "$1 $2" in
"is-enabled --quiet") [[ ${SSHD_ENABLED:-0} == 1 ]] ;;
"is-active --quiet") [[ ${SSHD_ACTIVE:-0} == 1 ]] ;;
"reload sshd.service") [[ ${SSHD_RELOAD_VALID:-1} == 1 ]] ;;
*) exit 2 ;;
esac
STUB

cat >"$stub_bin/sshd" <<'STUB'
#!/bin/bash
printf 'sshd %s\n' "$*" >>"${CALL_LOG:?}"
case $1 in
-t) [[ ${SSHD_SYNTAX_VALID:-1} == 1 ]] ;;
-T)
  printf 'PasswordAuthentication %s\n' "${SSHD_PASSWORD_AUTH:-no}"
  printf 'KbdInteractiveAuthentication %s\n' "${SSHD_KBD_AUTH:-no}"
  ;;
*) exit 2 ;;
esac
STUB

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"${CALL_LOG:?}"
exec "$@"
STUB

chmod +x "$stub_bin"/*

ssh-keygen -q -t ed25519 -N "" -f "$test_dir/key"
public_key=$(<"$test_dir/key.pub")

run_migration() {
  local scenario=$1
  local home="$test_dir/$scenario/home"
  local root="$test_dir/$scenario/root"
  local config="$root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf"

  mkdir -p "$home/.ssh" "${config%/*}"
  : >"$test_dir/$scenario.calls"
  if [[ ${AUTHORIZED_KEY_STATE:-valid} == "valid" ]]; then
    printf '%s\n' "$public_key" >"$home/.ssh/authorized_keys"
  elif [[ $AUTHORIZED_KEY_STATE == "invalid" ]]; then
    printf 'not a public key\n' >"$home/.ssh/authorized_keys"
  fi

  # Keep the privileged production destination fixed in the shipped migration.
  # For this isolated test only, rewrite that one assignment in the input fed to
  # bash so no scenario can touch the host's /etc.
  sed "s|^config=/etc/ssh/sshd_config.d/10-omarchy-hardening.conf$|config=$config|" "$migration" |
    HOME="$home" CALL_LOG="$test_dir/$scenario.calls" PATH="$stub_bin:$PATH" \
      SSHD_ENABLED="${SSHD_ENABLED:-0}" SSHD_ACTIVE="${SSHD_ACTIVE:-0}" \
      SSHD_SYNTAX_VALID="${SSHD_SYNTAX_VALID:-1}" \
      SSHD_PASSWORD_AUTH="${SSHD_PASSWORD_AUTH:-no}" \
      SSHD_KBD_AUTH="${SSHD_KBD_AUTH:-no}" \
      SSHD_RELOAD_VALID="${SSHD_RELOAD_VALID:-1}" \
      bash -euo pipefail
}

SSHD_ENABLED=0 SSHD_ACTIVE=0 run_migration disabled
[[ ! -e $test_dir/disabled/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] ||
  fail "SSH migration leaves a disabled daemon alone"
! grep -q '^sudo ' "$test_dir/disabled.calls" || fail "disabled SSH does not prompt for privileges"
pass "SSH migration no-ops when sshd is not enabled or active"

AUTHORIZED_KEY_STATE=missing SSHD_ENABLED=1 run_migration no-key >/dev/null
[[ ! -e $test_dir/no-key/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] ||
  fail "SSH migration must not disable passwords without an authorized key"
! grep -q '^sudo ' "$test_dir/no-key.calls" || fail "missing SSH key does not prompt for privileges"

AUTHORIZED_KEY_STATE=invalid SSHD_ENABLED=1 run_migration invalid-key >/dev/null
[[ ! -e $test_dir/invalid-key/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] ||
  fail "SSH migration must not trust a malformed authorized_keys file"
pass "SSH migration requires a usable authorized key before disabling passwords"

SSHD_ENABLED=1 SSHD_ACTIVE=1 run_migration active >/dev/null
config="$test_dir/active/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf"
grep -qxF "PasswordAuthentication no" "$config" || fail "SSH migration disables password authentication"
grep -qxF "KbdInteractiveAuthentication no" "$config" || fail "SSH migration disables keyboard-interactive authentication"
grep -qxF "sudo sshd -t" "$test_dir/active.calls" || fail "SSH migration validates sshd syntax"
grep -qxF "sudo sshd -T" "$test_dir/active.calls" || fail "SSH migration validates effective sshd settings"
grep -qxF "sudo systemctl reload sshd.service" "$test_dir/active.calls" || fail "SSH migration reloads an active daemon"
pass "SSH migration hardens and reloads an existing key-based SSH setup"

SSHD_ENABLED=1 SSHD_ACTIVE=0 run_migration stopped >/dev/null
[[ -e $test_dir/stopped/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] ||
  fail "SSH migration hardens an enabled but stopped daemon"
! grep -qF 'reload sshd.service' "$test_dir/stopped.calls" || fail "SSH migration must not start or reload a stopped daemon"
pass "SSH migration hardens an enabled daemon without starting it"

if SSHD_ENABLED=1 SSHD_ACTIVE=1 SSHD_PASSWORD_AUTH=yes run_migration ineffective >"$test_dir/ineffective.output" 2>&1; then
  fail "SSH migration must fail when password authentication remains effective"
fi
[[ ! -e $test_dir/ineffective/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] ||
  fail "SSH migration removes an ineffective config"
! grep -qF 'reload sshd.service' "$test_dir/ineffective.calls" || fail "SSH migration must not reload ineffective hardening"
pass "SSH migration stays pending when another rule keeps password authentication enabled"

if SSHD_ENABLED=1 SSHD_ACTIVE=1 SSHD_SYNTAX_VALID=0 run_migration invalid-config >"$test_dir/invalid-config.output" 2>&1; then
  fail "SSH migration must fail when sshd rejects its config"
fi
[[ ! -e $test_dir/invalid-config/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] ||
  fail "SSH migration removes a rejected config"
! grep -qF 'reload sshd.service' "$test_dir/invalid-config.calls" || fail "SSH migration must not reload rejected hardening"
pass "SSH migration fails safely when sshd rejects the config"
