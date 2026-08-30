#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_path="$test_tmp/aur-gate-bin"
mkdir -p "$mock_path"

# pacman reports every queried package missing until yay has run, so the
# pre-install check proceeds and the post-install check passes.
cat >"$mock_path/pacman" <<'EOF'
#!/bin/bash
if [[ -e "$TEST_TMP/yay-ran" ]]; then
  exit 0
fi
exit 1
EOF

cat >"$mock_path/yay" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >"$TEST_TMP/yay-command"
touch "$TEST_TMP/yay-ran"
EOF

chmod +x "$mock_path/pacman" "$mock_path/yay"

# The test runner has no terminal, so an unflagged call is the non-interactive
# caller the gate exists to stop.
gate_status=0
PATH="$mock_path:$ROOT/bin:$PATH" TEST_TMP="$test_tmp" \
  "$ROOT/bin/omarchy-pkg-aur-add" some-aur-pkg </dev/null 2>"$test_tmp/gate-stderr" || gate_status=$?
(( gate_status == 1 )) || fail "non-interactive AUR install is refused"
if [[ -e $test_tmp/yay-ran ]]; then
  fail "refused AUR install never reaches yay"
fi
grep -q "interactive confirmation" "$test_tmp/gate-stderr" || fail "refusal explains how to proceed"
pass "non-interactive AUR installs are refused with guidance"

rm -f "$test_tmp/yay-ran" "$test_tmp/yay-command"
PATH="$mock_path:$ROOT/bin:$PATH" TEST_TMP="$test_tmp" \
  "$ROOT/bin/omarchy-pkg-aur-add" --yes first-aur-pkg second-aur-pkg
[[ $(<"$test_tmp/yay-command") == "-S --noconfirm --needed first-aur-pkg second-aur-pkg" ]] ||
  fail "--yes passes the packages straight to yay"
pass "--yes installs without a prompt"

rm -f "$test_tmp/yay-ran" "$test_tmp/yay-command"
PATH="$mock_path:$ROOT/bin:$PATH" TEST_TMP="$test_tmp" \
  "$ROOT/bin/omarchy-pkg-aur-add" flag-position-pkg --yes
[[ $(<"$test_tmp/yay-command") == "-S --noconfirm --needed flag-position-pkg" ]] ||
  fail "--yes is accepted after package names"
pass "--yes works in any argument position"

usage_status=0
PATH="$mock_path:$ROOT/bin:$PATH" TEST_TMP="$test_tmp" \
  "$ROOT/bin/omarchy-pkg-aur-add" --yes 2>/dev/null || usage_status=$?
(( usage_status == 1 )) || fail "no packages named is a usage error"
pass "asking for --yes without packages is a usage error"
