#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

# Exercises migrations/1788256455.sh, which repairs an Omarchy-created
# /etc/pam.d/polkit-1 that lists pam_unix directly (dropping pam_faillock)
# instead of including system-auth. The migration keeps its production path
# fixed; as in sshd-hardening-migration-test.sh, this test rewrites that one
# assignment in the input fed to bash and stubs sudo so nothing touches the
# host's /etc.

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

migration="$ROOT/migrations/1788256455.sh"
stub_bin="$test_dir/bin"
mkdir -p "$stub_bin"

# sudo stub: log, optionally refuse (SUDO_ALLOWED=0), and optionally make a
# `tee` write vanish (WRITE_BREAKS=1) so the verification/restore path is
# exercised. Otherwise run the real command so cp/tee act on the temp file.
cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"${CALL_LOG:?}"
if [[ ${SUDO_ALLOWED:-1} != 1 ]]; then
  exit 1
fi
if [[ ${WRITE_BREAKS:-0} == 1 && $1 == tee ]]; then
  cat >/dev/null
  exit 0
fi
exec "$@"
STUB
chmod +x "$stub_bin"/*

# Run the migration against a polkit-1 file seeded with $1; leaves the result in
# "$test_dir/<scenario>/polkit-1" and records the exit status in migrate_rc.
migrate_rc=0
run_migration() {
  local scenario=$1 content=$2
  local dir="$test_dir/$scenario"
  local polkit="$dir/polkit-1"
  mkdir -p "$dir"
  printf '%s' "$content" >"$polkit"
  : >"$test_dir/$scenario.calls"

  migrate_rc=0
  sed "s|^polkit=/etc/pam.d/polkit-1\$|polkit=$polkit|" "$migration" |
    CALL_LOG="$test_dir/$scenario.calls" PATH="$stub_bin:$PATH" \
      SUDO_ALLOWED="${SUDO_ALLOWED:-1}" WRITE_BREAKS="${WRITE_BREAKS:-0}" \
      bash -euo pipefail >/dev/null 2>&1 || migrate_rc=$?
}

result() { cat "$test_dir/$1/polkit-1"; }

# The four layouts the old setup / remove commands leave behind.
fingerprint_stack='auth      [success=1 default=ignore] pam_exec.so quiet /usr/bin/omarchy-hw-laptop-closed
auth      sufficient pam_fprintd.so
auth      required pam_unix.so

account   required pam_unix.so
password  required pam_unix.so
session   required pam_unix.so
'
fido2_stack='auth      sufficient pam_u2f.so cue authfile=/etc/fido2/fido2
auth      required pam_unix.so

account   required pam_unix.so
password  required pam_unix.so
session   required pam_unix.so
'
both_stack='auth      [success=1 default=ignore] pam_exec.so quiet /usr/bin/omarchy-hw-laptop-closed
auth      sufficient pam_fprintd.so
auth      sufficient pam_u2f.so cue authfile=/etc/fido2/fido2
auth      required pam_unix.so

account   required pam_unix.so
password  required pam_unix.so
session   required pam_unix.so
'
# What both remove commands leave: their own marker lines stripped, the bare
# pam_unix stack (and no marker) behind.
markerless_stack='auth      required pam_unix.so

account   required pam_unix.so
password  required pam_unix.so
session   required pam_unix.so
'
fixed_stack='auth      sufficient pam_fprintd.so
auth      include system-auth
account   include system-auth
password  include system-auth
session   include system-auth
'
# An administrator's own stack that happens to use pam_fprintd but carries an
# extra directive Omarchy never writes.
admin_stack='auth      sufficient pam_fprintd.so
auth      required pam_unix.so
auth      optional pam_permit.so
account   required pam_unix.so
password  required pam_unix.so
session   required pam_unix.so
'

# Every phase of a repaired stack must defer to system-auth and no bare pam_unix
# may remain in the account/password/session block.
assert_repaired() {
  local scenario=$1 phase
  for phase in auth account password session; do
    grep -qE "^${phase}[[:space:]]+include[[:space:]]+system-auth" <<<"$(result "$scenario")" ||
      fail "$scenario: $phase defers to system-auth" "$(result "$scenario")"
  done
  ! grep -qE '^(account|password|session)[[:space:]]+required[[:space:]]+pam_unix' <<<"$(result "$scenario")" ||
    fail "$scenario: no bare pam_unix remains" "$(result "$scenario")"
}

run_migration fingerprint "$fingerprint_stack"
(( migrate_rc == 0 )) || fail "fingerprint stack migrates cleanly"
assert_repaired fingerprint
grep -qF 'pam_fprintd.so' <<<"$(result fingerprint)" || fail "fingerprint line is preserved"
grep -qF 'omarchy-hw-laptop-closed' <<<"$(result fingerprint)" || fail "clamshell gate is preserved"
pass "migration repairs the fingerprint stack and keeps its hardware-auth lines"

run_migration fido2 "$fido2_stack"
(( migrate_rc == 0 )) || fail "fido2 stack migrates cleanly"
assert_repaired fido2
grep -qF 'pam_u2f.so cue authfile=/etc/fido2/fido2' <<<"$(result fido2)" || fail "FIDO2 line is preserved"
pass "migration repairs the FIDO2 stack and keeps its hardware-auth line"

run_migration both "$both_stack"
(( migrate_rc == 0 )) || fail "combined stack migrates cleanly"
assert_repaired both
grep -qF 'pam_fprintd.so' <<<"$(result both)" && grep -qF 'pam_u2f.so' <<<"$(result both)" ||
  fail "both hardware-auth lines are preserved"
pass "migration repairs a combined fingerprint+FIDO2 stack"

run_migration markerless "$markerless_stack"
(( migrate_rc == 0 )) || fail "markerless stack migrates cleanly"
assert_repaired markerless
pass "migration repairs the markerless post-removal stack"

run_migration comment "# managed by omarchy
$fingerprint_stack"
(( migrate_rc == 0 )) || fail "commented stack migrates cleanly"
assert_repaired comment
grep -qxF '# managed by omarchy' <<<"$(result comment)" || fail "comments are preserved through the rewrite"
pass "migration repairs a commented stack and preserves the comment"

run_migration fixed "$fixed_stack"
[[ "$(result fixed)" == "$(printf '%s' "$fixed_stack")" ]] || fail "an already-fixed stack is left byte-for-byte unchanged"
! grep -q '^sudo ' "$test_dir/fixed.calls" || fail "an already-fixed stack triggers no privileged writes"
pass "migration is idempotent: an already-fixed stack is untouched"

run_migration admin "$admin_stack"
[[ "$(result admin)" == "$(printf '%s' "$admin_stack")" ]] || fail "an administrator-authored stack is left unchanged"
! grep -q '^sudo ' "$test_dir/admin.calls" || fail "an administrator-authored stack triggers no privileged writes"
pass "migration refuses a stack carrying non-Omarchy directives"

# Privilege failure is the retryable case: the migration must exit non-zero so
# omarchy-migrate does not record it complete, and must leave the file unchanged.
SUDO_ALLOWED=0 run_migration no-sudo "$fingerprint_stack"
(( migrate_rc != 0 )) || fail "the migration stays pending when privileges are unavailable"
[[ "$(result no-sudo)" == "$(printf '%s' "$fingerprint_stack")" ]] || fail "a failed repair leaves the original file intact"
pass "migration exits non-zero and preserves the file when sudo is refused"

# A write that does not take effect must be caught by verification, restored,
# and reported as a failure rather than silently marked complete.
WRITE_BREAKS=1 run_migration verify-fail "$fingerprint_stack"
(( migrate_rc != 0 )) || fail "a failed verification exits non-zero"
[[ "$(result verify-fail)" == "$(printf '%s' "$fingerprint_stack")" ]] || fail "a failed verification restores the original file"
pass "migration exits non-zero and restores when the write cannot be verified"
