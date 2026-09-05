#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -r "$tmp_dir"' EXIT

# The command writes to /etc/pam.d/passwd, an absolute path we must not touch
# outside an Omarchy machine. Follow the brcmfmac-supplicant pattern: copy the
# leaf into the sandbox and rewrite the absolute paths into it.
pam_file="$tmp_dir/etc/pam.d/passwd"
mkdir -p "$tmp_dir/etc/pam.d"
printf '#%%PAM-1.0\npassword include system-auth\n' >"$pam_file"

# A full copy with the absolute paths rewritten; do not source the original,
# or it would touch the real /etc/pam.d/passwd.
{
  echo '#!/bin/bash'
  sed -e "s|/etc/pam.d/passwd|$pam_file|g" "$ROOT/bin/omarchy-user-password"
} >"$tmp_dir/leaf.sh"

cat >"$tmp_dir/gnome-keyring-daemon" <<'EOF'
#!/bin/bash
exit 0
EOF

cat >"$tmp_dir/sudo" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$TEST_ARGS"
# tee -a emulation: the caller pipes the new line in on stdin
cat >>"$3"
EOF

cat >"$tmp_dir/passwd" <<'EOF'
#!/bin/bash
printf 'passwd ran\n' >"$TEST_PASSWD_RAN"
EOF

chmod +x "$tmp_dir/gnome-keyring-daemon" "$tmp_dir/sudo" "$tmp_dir/passwd"
export PATH="$tmp_dir:$ROOT/bin:$PATH"
export TEST_ARGS="$tmp_dir/args" TEST_PASSWD_RAN="$tmp_dir/ran"

# First run: the keyring line is appended once and passwd still runs.
bash -euo pipefail "$tmp_dir/leaf.sh" </dev/null >/dev/null

grep -q '^password.*pam_gnome_keyring\.so' "$pam_file" ||
  fail "user password adds the keyring sync line to the passwd PAM stack"
[[ -e $TEST_PASSWD_RAN ]] || fail "user password still runs passwd"
grep -Fxq "tee" "$TEST_ARGS" && grep -Fxq -- "-a" "$TEST_ARGS" &&
  grep -Fxq "$pam_file" "$TEST_ARGS" ||
  fail "user password appends the keyring line via sudo tee -a"

# Second run: idempotent, no duplicate line, passwd still runs.
lines_before=$(wc -l <"$pam_file")
rm -f "$TEST_PASSWD_RAN" "$TEST_ARGS"
bash -euo pipefail "$tmp_dir/leaf.sh" </dev/null >/dev/null

(( $(wc -l <"$pam_file") == lines_before )) ||
  fail "user password does not append the keyring line twice"
[[ -e $TEST_PASSWD_RAN ]] || fail "second run still runs passwd"
[[ ! -e $TEST_ARGS ]] || fail "second run does not append again"

# A sudo stub that fails, the way a cancelled sudo prompt does. The command
# must refuse to change the password: changing it without the keyring line
# would orphan the keyring with no way back through a later change. Uses a
# fresh PAM file, since the runs above already added the line to $pam_file.
cat >"$tmp_dir/sudo-fail" <<'EOF'
#!/bin/bash
echo "sudo: a password is required" >&2
exit 1
EOF
chmod +x "$tmp_dir/sudo-fail"

pam_abort="$tmp_dir/etc/pam.d/passwd-abort"
printf '#%%PAM-1.0\npassword include system-auth\n' >"$pam_abort"
sed -e "s|/etc/pam.d/passwd|$pam_abort|g" -e "s|sudo tee|$tmp_dir/sudo-fail tee|g" \
  "$ROOT/bin/omarchy-user-password" >"$tmp_dir/leaf-nofail.sh"
rm -f "$TEST_PASSWD_RAN" "$TEST_ARGS"
bash -euo pipefail "$tmp_dir/leaf-nofail.sh" </dev/null >"$tmp_dir/abort-msg" 2>&1 &&
  fail "user password aborts when the PAM append is refused"
[[ ! -e $TEST_PASSWD_RAN ]] || fail "aborted run does not change the password"
grep -q "NOT changed" "$tmp_dir/abort-msg" ||
  fail "abort message explains the refusal" "$(cat "$tmp_dir/abort-msg")"
pass "user password aborts before passwd when the PAM append fails"

# The migration installs the same PAM line idempotently, so a plain
# `passwd` on the terminal is covered too. Runs as the user under
# bash -euo pipefail, like omarchy-migrate does.
migration="$ROOT/migrations/1788120000.sh"
pam2="$tmp_dir/etc/pam.d/passwd-migration"
mkdir -p "$tmp_dir/etc/pam.d"
printf '#%%PAM-1.0\npassword include system-auth\n' >"$pam2"

run_migration() {
  local pam_target="$1"
  sed -e "s|/etc/pam.d/passwd|$pam_target|g" -e "s|sudo tee|$tmp_dir/sudo tee|g" \
    -e "s|omarchy-cmd-missing gnome-keyring-daemon|false|g" \
    "$migration" >"$tmp_dir/migration.sh"
  PATH="$tmp_dir:$PATH" HOME="$tmp_dir" \
    bash -euo pipefail "$tmp_dir/migration.sh" </dev/null >/dev/null 2>&1
}

# The omarchy-cmd-missing substitution above makes the guard fail, so the
# migration proceeds to the PAM append.
run_migration "$pam2"
grep -q '^password.*pam_gnome_keyring\.so' "$pam2" ||
  fail "migration installs the keyring PAM line" "$(cat "$pam2")"
pass "migration installs the keyring PAM line"

lines_before=$(wc -l <"$pam2")
run_migration "$pam2"
(( $(wc -l <"$pam2") == lines_before )) ||
  fail "migration is idempotent" "$(cat "$pam2")"
pass "migration is idempotent"

pass "user password wires the keyring into passwd PAM exactly once and runs passwd"
