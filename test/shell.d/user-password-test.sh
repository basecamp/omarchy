#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -r "$tmp_dir"' EXIT

cat >"$tmp_dir/gum" <<'EOF'
#!/bin/bash
IFS= read -r line <"$TEST_INPUTS"
tail -n +2 "$TEST_INPUTS" >"$TEST_INPUTS.next"
mv "$TEST_INPUTS.next" "$TEST_INPUTS"
printf '%s\n' "$line"
EOF

cat >"$tmp_dir/sudo" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$TEST_ARGS"
cat >"$TEST_STDIN"
EOF

chmod +x "$tmp_dir/gum" "$tmp_dir/sudo"
export PATH="$tmp_dir:$ROOT/bin:$PATH"
export USER=tester
export TEST_ARGS="$tmp_dir/args" TEST_INPUTS="$tmp_dir/inputs" TEST_STDIN="$tmp_dir/stdin"

printf '\n' >"$TEST_INPUTS"
if "$ROOT/bin/omarchy-user-password" >/dev/null; then
  fail "user password rejects an empty passphrase"
fi
[[ ! -e $TEST_ARGS ]] || fail "user password does not run chpasswd for an empty passphrase"

printf 'secret123\n*\n' >"$TEST_INPUTS"
if "$ROOT/bin/omarchy-user-password" >/dev/null; then
  fail "user password rejects a mismatched confirmation"
fi
[[ ! -e $TEST_ARGS ]] || fail "user password does not run chpasswd for a mismatched confirmation"

printf 'new password\nnew password\n' >"$TEST_INPUTS"
"$ROOT/bin/omarchy-user-password" >/dev/null

[[ $(<"$TEST_ARGS") == "chpasswd" ]] || fail "user password runs chpasswd" "$(cat "$TEST_ARGS")"
[[ $(<"$TEST_STDIN") == $'tester:new password\nroot:new password' ]] ||
  fail "user password sets the same passphrase on the login user and on root" "$(cat "$TEST_STDIN")"
pass "user password rejects empty and mismatched passphrases and updates user and root together"

grep -Fq 'omarchy-user-password' "$ROOT/default/omarchy/omarchy-menu.jsonc" ||
  fail "password menu updates user and root through omarchy-user-password"
if grep -Fq 'omarchy-launch-floating-terminal-with-presentation passwd' "$ROOT/default/omarchy/omarchy-menu.jsonc"; then
  fail "password menu no longer runs passwd alone"
fi
pass "password menu points at omarchy-user-password"
