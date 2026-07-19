#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -r "$tmp_dir"' EXIT

cat >"$tmp_dir/blkid" <<'EOF'
#!/bin/bash
echo /dev/test-luks
EOF

cat >"$tmp_dir/gum" <<'EOF'
#!/bin/bash
head -n 1 "$TEST_INPUTS"
sed -i '1d' "$TEST_INPUTS"
EOF

cat >"$tmp_dir/sudo" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$TEST_ARGS"
cat >"$TEST_STDIN"
EOF

chmod +x "$tmp_dir/blkid" "$tmp_dir/gum" "$tmp_dir/sudo"
export PATH="$tmp_dir:$ROOT/bin:$PATH"
export TEST_ARGS="$tmp_dir/args" TEST_INPUTS="$tmp_dir/inputs" TEST_STDIN="$tmp_dir/stdin"

printf '\n' >"$TEST_INPUTS"
if "$ROOT/bin/omarchy-drive-password" >/dev/null; then
  fail "drive password rejects an empty passphrase"
fi
[[ ! -e $TEST_ARGS ]] || fail "drive password does not run cryptsetup for an empty passphrase"

printf 'secret123\n*\n' >"$TEST_INPUTS"
if "$ROOT/bin/omarchy-drive-password" >/dev/null; then
  fail "drive password rejects a mismatched confirmation"
fi
[[ ! -e $TEST_ARGS ]] || fail "drive password does not run cryptsetup for a mismatched confirmation"

printf 'new password\nnew password\n' >"$TEST_INPUTS"
"$ROOT/bin/omarchy-drive-password" >/dev/null

[[ $(<"$TEST_STDIN") == "new password" ]] || fail "drive password passes the validated passphrase without a newline"
grep -F 'cryptsetup luksChangeKey' "$TEST_ARGS" >/dev/null || fail "drive password changes the LUKS key"
grep -Fx /dev/test-luks "$TEST_ARGS" >/dev/null || fail "drive password targets the selected drive"
pass "drive password rejects empty and mismatched passphrases and passes validated input to cryptsetup"
