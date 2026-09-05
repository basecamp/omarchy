#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
b="$t/bin"; mkdir "$b"
test_uid=$(/usr/bin/id -u)
cat >"$b/systemctl" <<'SH'
#!/bin/bash
echo "systemctl $*" >>"$LOG"
case $1 in is-active) [[ -e $STATE/active ]];; is-enabled) [[ -e $STATE/enabled ]];; reload) [[ ${RELOAD_FAIL:-0} != 1 ]];; disable) rm -f "$STATE/active" "$STATE/enabled";; esac
SH
cat >"$b/ssh-keygen" <<'SH'
#!/bin/bash
[[ $1 != -A ]] || { echo hostkeys >>"$LOG"; exit "${HOSTKEY_FAIL:-0}"; }
exec /usr/bin/ssh-keygen "$@"
SH
cat >"$b/sshd" <<'SH'
#!/bin/bash
[[ $1 != -t ]] || exit "${T_FAIL:-0}"
if [[ " $* " == *' -C '* ]]; then echo "PasswordAuthentication ${MATCH_PASS_AUTH:-${PASS_AUTH:-no}}"; else echo "PasswordAuthentication ${PASS_AUTH:-no}"; fi
echo 'KbdInteractiveAuthentication no'
echo 'AuthenticationMethods publickey'
echo 'PubkeyAuthentication yes'
echo 'AuthorizedKeysFile .ssh/authorized_keys'
SH
cat >"$b/sudo" <<'SH'
#!/bin/bash
if [[ $1 == install ]]; then [[ ${INSTALL_FAIL:-0} != 1 ]] || exit 1; a=("$@"); d=${a[-1]}; mkdir -p "${d%/*}"; exec /usr/bin/install -m0644 "${a[-2]}" "$d"; fi
exec "$@"
SH
cat >"$b/id" <<'SH'
#!/bin/bash
echo "${TEST_UID:?}"
SH
cat >"$b/getent" <<'SH'
#!/bin/bash
echo "audit:x:${TEST_UID:?}:${TEST_UID}:Audit:${PASSWD_HOME:?}:/bin/bash"
SH
cat >"$b/stat" <<'SH'
#!/bin/bash
if [[ ${FOREIGN_KEY_OWNER:-0} == 1 && $* == *"%u"* && ${*: -1} == */authorized_keys ]]; then echo 9999; else exec /usr/bin/stat "$@"; fi
SH
chmod +x "$b"/*
ssh-keygen -q -t ed25519 -N '' -f "$t/key"
key=$(<"$t/key.pub")
run_migration() {
  local n=$1; local d="$t/$n"; mkdir -p "$d/home/.ssh" "$d/etc/ssh/sshd_config.d" "$d/state"; [[ -e $d/etc/ssh/sshd_config ]] || echo 'Include /etc/ssh/sshd_config.d/*.conf' >"$d/etc/ssh/sshd_config"; : >"$d/log"
  [[ ${NO_KEY:-0} == 1 ]] || printf '%s\n' "${MIGRATION_KEY:-$key}" >"$d/home/.ssh/authorized_keys"
  chmod 700 "$d/home" "$d/home/.ssh"; [[ ! -e $d/home/.ssh/authorized_keys ]] || chmod 600 "$d/home/.ssh/authorized_keys"
  if [[ ${SYMLINK_SSH:-0} == 1 ]]; then mv "$d/home/.ssh" "$d/home/ssh-real"; ln -s ssh-real "$d/home/.ssh"; fi
  [[ ${ACTIVE:-0} != 1 ]] || touch "$d/state/active"; [[ ${ENABLED:-0} != 1 ]] || touch "$d/state/enabled"
  [[ ${ADMIN_LEGACY:-0} == 1 ]] && echo 'PasswordAuthentication yes' >"$d/etc/ssh/sshd_config.d/10-omarchy-hardening.conf" || printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' >"$d/etc/ssh/sshd_config.d/10-omarchy-hardening.conf"
  sed -e "s#^legacy_config=.*#legacy_config=$d/etc/ssh/sshd_config.d/10-omarchy-hardening.conf#" -e "s#^key_only_config=.*#key_only_config=$d/etc/ssh/sshd_config.d/00-omarchy-key-only.conf#" -e "s#^main_config=.*#main_config=$d/etc/ssh/sshd_config#" -e "s#^dropin_dir=.*#dropin_dir=$d/etc/ssh/sshd_config.d#" -e "s#/usr/bin/id#$b/id#g" -e "s#/usr/bin/getent#$b/getent#g" -e "s#/usr/bin/stat#$b/stat#g" "$ROOT/migrations/1788163637.sh" |
    HOME="$d/home" PATH="$b:/usr/bin" LOG="$d/log" STATE="$d/state" TEST_UID="$test_uid" PASSWD_HOME="${PASSWD_HOME_OVERRIDE:-$d/home}" FOREIGN_KEY_OWNER="${FOREIGN_KEY_OWNER:-0}" PASS_AUTH="${PASS_AUTH:-no}" MATCH_PASS_AUTH="${MATCH_PASS_AUTH:-}" RELOAD_FAIL="${RELOAD_FAIL:-0}" INSTALL_FAIL="${INSTALL_FAIL:-0}" bash
}
ACTIVE=1 ENABLED=1 run_migration active
[[ -f $t/active/etc/ssh/sshd_config.d/00-omarchy-key-only.conf && ! -e $t/active/etc/ssh/sshd_config.d/10-omarchy-hardening.conf ]]; grep -q 'systemctl reload' "$t/active/log"
ENABLED=1 run_migration stopped; ! grep -q 'systemctl reload' "$t/stopped/log"; [[ -e $t/stopped/state/enabled ]]
NO_KEY=1 ACTIVE=1 ENABLED=1 run_migration no-key; [[ ! -e $t/no-key/state/active && ! -e $t/no-key/state/enabled ]]
MIGRATION_KEY=invalid ACTIVE=1 run_migration invalid-key; [[ ! -e $t/invalid-key/state/active ]]
FOREIGN_KEY_OWNER=1 ACTIVE=1 ENABLED=1 run_migration foreign-owner; [[ ! -e $t/foreign-owner/state/active && ! -e $t/foreign-owner/etc/ssh/sshd_config.d/00-omarchy-key-only.conf ]]
SYMLINK_SSH=1 ACTIVE=1 run_migration symlink-ssh; [[ ! -e $t/symlink-ssh/state/active ]]
PASSWD_HOME_OVERRIDE="$t/home-mismatch/elsewhere" ACTIVE=1 run_migration home-mismatch; [[ ! -e $t/home-mismatch/state/active ]]
mkdir -p "$t/ambiguous/etc/ssh"; printf 'PasswordAuthentication yes\nInclude /etc/ssh/sshd_config.d/*.conf\n' >"$t/ambiguous/etc/ssh/sshd_config"; ACTIVE=1 run_migration ambiguous; [[ ! -e $t/ambiguous/state/active ]]
PASS_AUTH=yes ACTIVE=1 run_migration match-bypass; [[ ! -e $t/match-bypass/state/active && ! -e $t/match-bypass/etc/ssh/sshd_config.d/00-omarchy-key-only.conf ]]
MATCH_PASS_AUTH=yes ACTIVE=1 run_migration matched-only; [[ ! -e $t/matched-only/state/active && ! -e $t/matched-only/etc/ssh/sshd_config.d/00-omarchy-key-only.conf ]]
RELOAD_FAIL=1 ACTIVE=1 ENABLED=1 run_migration reload-fail; [[ ! -e $t/reload-fail/state/active && ! -e $t/reload-fail/state/enabled && -e $t/reload-fail/etc/ssh/sshd_config.d/00-omarchy-key-only.conf ]]
ADMIN_LEGACY=1 ACTIVE=1 run_migration admin; grep -qxF 'PasswordAuthentication yes' "$t/admin/etc/ssh/sshd_config.d/10-omarchy-hardening.conf"; [[ -e $t/admin/state/active ]]
if INSTALL_FAIL=1 ACTIVE=1 run_migration install-fail; then fail 'migration install failure completes'; fi; [[ -e $t/install-fail/state/active ]]
run_migration idempotent; run_migration idempotent
pass "key-only SSH migration repairs, disables, preserves, rolls back, and reruns safely"
