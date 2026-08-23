#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1787422694.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin" "$test_dir/pam.d"

# sudo runs the real command, so sed acts on the redirected pam.d below.
cat >"$test_dir/bin/sudo" <<'STUB'
#!/bin/bash

exec "$@"
STUB

chmod +x "$test_dir/bin/"*

pam_dir="$test_dir/pam.d"
gate="auth      [success=1 default=ignore] pam_exec.so quiet /usr/bin/omarchy-hw-laptop-closed"
gated="auth      [success=1 default=ignore] pam_exec.so quiet quiet_log /usr/bin/omarchy-hw-laptop-closed"

write_stack() {
  printf '%s\nauth      sufficient pam_fprintd.so\nauth      include system-auth\n' "$1"
}

reset_machine() {
  rm -f "$pam_dir/sudo" "$pam_dir/polkit-1"
}

run_migration() {
  OMARCHY_LID_GATE_PAM_DIR="$pam_dir" \
    PATH="$test_dir/bin:$PATH" \
    bash -euo pipefail "$migration" >/dev/null
}

# The machines this migration exists for: the gate is in place from 1784818437
# or an older setup script, with no quiet_log.
reset_machine
write_stack "$gate" >"$pam_dir/sudo"
write_stack "$gate" >"$pam_dir/polkit-1"
run_migration

grep -qxF "$gated" "$pam_dir/sudo" ||
  fail "migration adds quiet_log to the sudo gate" "$(cat "$pam_dir/sudo")"
pass "migration adds quiet_log to the sudo gate"

grep -qxF "$gated" "$pam_dir/polkit-1" ||
  fail "migration adds quiet_log to the polkit gate" "$(cat "$pam_dir/polkit-1")"
pass "migration adds quiet_log to the polkit gate"

# The gate is one line of an auth stack; everything under it must survive.
grep -qx 'auth      sufficient pam_fprintd.so' "$pam_dir/sudo" &&
  grep -qx 'auth      include system-auth' "$pam_dir/sudo" ||
  fail "migration leaves the rest of the stack alone" "$(cat "$pam_dir/sudo")"
pass "migration leaves the rest of the stack alone"

# Migrations are marker-file based per user, so a second account runs this again
# on a machine that is already converted.
before=$(cat "$pam_dir/sudo")
run_migration

[[ $(cat "$pam_dir/sudo") == "$before" ]] ||
  fail "migration is idempotent on a second run" "$(cat "$pam_dir/sudo")"
pass "migration is idempotent on a second run"

# No fingerprint reader set up means no gate to convert, and the stack must not
# be rewritten on the way past.
reset_machine
printf '#%%PAM-1.0\nauth      include system-auth\n' >"$pam_dir/sudo"
before=$(cat "$pam_dir/sudo")
run_migration

[[ $(cat "$pam_dir/sudo") == "$before" ]] ||
  fail "migration leaves an ungated stack alone" "$(cat "$pam_dir/sudo")"
pass "migration leaves an ungated stack alone"

# polkit-1 is not shipped by a package; omarchy writes it during fingerprint
# setup, so it is absent on a machine that never ran one.
reset_machine
write_stack "$gate" >"$pam_dir/sudo"
run_migration

[[ ! -e $pam_dir/polkit-1 ]] ||
  fail "migration does not create a missing polkit-1"
pass "migration does not create a missing polkit-1"

# Only the gate line carries the substitution, so an unrelated pam_exec the user
# added keeps its own options.
reset_machine
{
  printf '%s\n' "$gate"
  printf 'auth      optional pam_exec.so quiet /usr/local/bin/something-else\n'
} >"$pam_dir/sudo"
run_migration

grep -qx 'auth      optional pam_exec.so quiet /usr/local/bin/something-else' "$pam_dir/sudo" ||
  fail "migration leaves an unrelated pam_exec alone" "$(cat "$pam_dir/sudo")"
pass "migration leaves an unrelated pam_exec alone"
