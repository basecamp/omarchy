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
"disable --now") ;;
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
if [[ ${SUDO_ALLOWED:-1} != 1 ]]; then
  exit 1
fi
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
  chmod "${HOME_MODE:-755}" "$home"
  : >"$test_dir/$scenario.calls"
  case "${AUTHORIZED_KEY_STATE:-valid}" in
  valid) printf '%s\n' "$public_key" >"$home/.ssh/authorized_keys" ;;
  invalid) printf 'not a public key\n' >"$home/.ssh/authorized_keys" ;;
  private) cat "$test_dir/key" >"$home/.ssh/authorized_keys" ;;
  symlink)
    printf '%s\n' "$public_key" >"$home/.ssh/imported_key"
    ln -s imported_key "$home/.ssh/authorized_keys"
    ;;
  unreadable)
    printf '%s\n' "$public_key" >"$home/.ssh/authorized_keys"
    chmod 000 "$home/.ssh/authorized_keys"
    ;;
  esac
  if [[ ${LOOSE_SSH_PERMS:-0} == 1 ]]; then
    chmod 755 "$home/.ssh"
    chmod 644 "$home/.ssh/authorized_keys"
  fi
  if [[ ${ALREADY_HARDENED:-0} == 1 ]]; then
    printf 'PasswordAuthentication no\n' >"$config"
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
      SUDO_ALLOWED="${SUDO_ALLOWED:-1}" \
      bash -euo pipefail
}

sshd_disabled() {
  grep -qxF "sudo systemctl disable --now sshd.service" "$test_dir/$1.calls"
}

SSHD_ENABLED=0 SSHD_ACTIVE=0 run_migration disabled
[[ ! -e $test_dir/disabled/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] ||
  fail "SSH migration leaves a disabled daemon alone"
! grep -q '^sudo ' "$test_dir/disabled.calls" || fail "disabled SSH does not prompt for privileges"
pass "SSH migration no-ops when sshd is not enabled or active"

ALREADY_HARDENED=1 SSHD_ENABLED=1 SSHD_ACTIVE=1 run_migration hardened >/dev/null
[[ ! -s $test_dir/hardened.calls ]] || fail "an already-hardened machine must not touch sshd or prompt"
grep -qxF "PasswordAuthentication no" "$test_dir/hardened/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf" ||
  fail "the existing hardening config is left alone"
pass "SSH migration no-ops when the hardening config already exists"

# Without a usable key, sshd only accepts password logins — the hole the old
# setup command could leave open. The migration closes it by disabling sshd.
AUTHORIZED_KEY_STATE=missing SSHD_ENABLED=1 run_migration no-key >/dev/null
[[ ! -e $test_dir/no-key/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] ||
  fail "SSH migration must not write the hardening config without an authorized key"
sshd_disabled no-key || fail "SSH migration disables a password-only sshd"
pass "SSH migration disables sshd when no key is authorized"

AUTHORIZED_KEY_STATE=invalid SSHD_ENABLED=1 run_migration invalid-key >/dev/null
sshd_disabled invalid-key || fail "a malformed authorized_keys leaves sshd password-only"
pass "SSH migration disables sshd when authorized_keys holds no valid key"

# ssh-keygen -lf accepts a whole private-key file, so only a per-line check
# catches the classic `cp id_ed25519 authorized_keys` slip that sshd cannot use.
AUTHORIZED_KEY_STATE=private SSHD_ENABLED=1 run_migration private-key >/dev/null
[[ ! -e $test_dir/private-key/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] ||
  fail "SSH migration must not treat a private key as an authorized key"
sshd_disabled private-key || fail "a private-key authorized_keys leaves sshd password-only"
pass "SSH migration disables sshd when authorized_keys holds a private key"

# A dotfiles-managed symlink with a working key is a key-based setup, not a
# keyless one; it must be hardened, never disabled.
AUTHORIZED_KEY_STATE=symlink SSHD_ENABLED=1 SSHD_ACTIVE=1 run_migration symlink-key >/dev/null
grep -qxF "PasswordAuthentication no" "$test_dir/symlink-key/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf" ||
  fail "SSH migration hardens a symlinked authorized_keys with a valid key"
! sshd_disabled symlink-key || fail "SSH migration must not disable sshd when the symlinked key is usable"
pass "SSH migration follows an authorized_keys symlink to its key"

# An unreadable file answers neither "keyless" nor "key-based": touch nothing.
if (( EUID != 0 )); then
  AUTHORIZED_KEY_STATE=unreadable SSHD_ENABLED=1 run_migration unreadable >/dev/null
  [[ ! -e $test_dir/unreadable/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] ||
    fail "SSH migration must not harden against an unverifiable authorized_keys"
  ! grep -q '^sudo ' "$test_dir/unreadable.calls" || fail "an unreadable authorized_keys does not prompt or disable"
  pass "SSH migration leaves an unreadable authorized_keys alone"
fi

# StrictModes makes sshd ignore authorized_keys under a group-writable home,
# so the key that validated would be unusable and passwords the only way in.
HOME_MODE=775 SSHD_ENABLED=1 run_migration loose-home >/dev/null
[[ ! -e $test_dir/loose-home/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] ||
  fail "SSH migration must not disable passwords when sshd would ignore the key"
! grep -q '^sudo ' "$test_dir/loose-home.calls" || fail "a group-writable home does not prompt for privileges"
pass "SSH migration leaves a group-writable home directory alone"

LOOSE_SSH_PERMS=1 SSHD_ENABLED=1 SSHD_ACTIVE=1 run_migration active >/dev/null
config="$test_dir/active/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf"
grep -qxF "PasswordAuthentication no" "$config" || fail "SSH migration disables password authentication"
grep -qxF "KbdInteractiveAuthentication no" "$config" || fail "SSH migration disables keyboard-interactive authentication"
[[ $(stat -c '%a' "$test_dir/active/home/.ssh") == "700" ]] ||
  fail "SSH migration tightens ~/.ssh so StrictModes accepts the key"
[[ $(stat -c '%a' "$test_dir/active/home/.ssh/authorized_keys") == "600" ]] ||
  fail "SSH migration tightens authorized_keys so StrictModes accepts the key"
grep -qxF "sudo sshd -t" "$test_dir/active.calls" || fail "SSH migration validates sshd syntax"
grep -qxF "sudo sshd -T" "$test_dir/active.calls" || fail "SSH migration validates effective sshd settings"
grep -qxF "sudo systemctl reload sshd.service" "$test_dir/active.calls" || fail "SSH migration reloads an active daemon"
pass "SSH migration hardens and reloads an existing key-based SSH setup"

SSHD_ENABLED=1 SSHD_ACTIVE=0 run_migration stopped >/dev/null
[[ -e $test_dir/stopped/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] ||
  fail "SSH migration hardens an enabled but stopped daemon"
! grep -qF 'reload sshd.service' "$test_dir/stopped.calls" || fail "SSH migration must not start or reload a stopped daemon"
pass "SSH migration hardens an enabled daemon without starting it"

# Conditions the migration cannot repair complete with a notice — leaving the
# machine as it was — so they never block the migrations queued behind this one.
SSHD_ENABLED=1 SSHD_ACTIVE=1 SSHD_PASSWORD_AUTH=yes run_migration ineffective >"$test_dir/ineffective.output" 2>&1 ||
  fail "an ineffective drop-in must complete without blocking later migrations"
[[ ! -e $test_dir/ineffective/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] ||
  fail "SSH migration removes an ineffective config"
! grep -qF 'reload sshd.service' "$test_dir/ineffective.calls" || fail "SSH migration must not reload ineffective hardening"
pass "SSH migration backs off when another rule keeps password authentication enabled"

SSHD_ENABLED=1 SSHD_ACTIVE=1 SSHD_SYNTAX_VALID=0 run_migration invalid-config >"$test_dir/invalid-config.output" 2>&1 ||
  fail "a rejected config must complete without blocking later migrations"
[[ ! -e $test_dir/invalid-config/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] ||
  fail "SSH migration removes a rejected config"
! grep -qF 'reload sshd.service' "$test_dir/invalid-config.calls" || fail "SSH migration must not reload rejected hardening"
pass "SSH migration backs off when sshd rejects the config"

# The installed config is valid, so a failed reload only delays it until the
# next sshd restart; keep it staged rather than failing or removing it.
SSHD_ENABLED=1 SSHD_ACTIVE=1 SSHD_RELOAD_VALID=0 run_migration reload-fail >"$test_dir/reload-fail.output" 2>&1 ||
  fail "a failed reload must complete without blocking later migrations"
[[ -e $test_dir/reload-fail/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] ||
  fail "a failed reload keeps the valid hardening config staged"
pass "SSH migration keeps the hardening staged when sshd cannot reload"

# Privileges are the one genuinely retryable failure: stay pending so the
# login notifier prompts for a terminal run.
if SUDO_ALLOWED=0 SSHD_ENABLED=1 SSHD_ACTIVE=1 run_migration no-sudo >"$test_dir/no-sudo.output" 2>&1; then
  fail "SSH migration must stay pending when privileges are unavailable"
fi
[[ ! -e $test_dir/no-sudo/root/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]] ||
  fail "no hardening config is left behind without privileges"
pass "SSH migration stays pending until privileges are granted"

if SUDO_ALLOWED=0 AUTHORIZED_KEY_STATE=missing SSHD_ENABLED=1 run_migration no-sudo-keyless >"$test_dir/no-sudo-keyless.output" 2>&1; then
  fail "SSH migration must stay pending when it cannot disable a password-only sshd"
fi
pass "SSH migration stays pending when disabling sshd needs privileges"
