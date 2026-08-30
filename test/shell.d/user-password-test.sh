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

pass "user password wires the keyring into passwd PAM exactly once and runs passwd"
