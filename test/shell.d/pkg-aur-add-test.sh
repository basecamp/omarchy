#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_bin=$(mktemp -d)
state_dir=$(mktemp -d)
log_file=$(mktemp)
trap 'rm -rf "$test_bin" "$state_dir"; rm -f "$log_file"' EXIT

# pacman -Q only ever knows packages by their real (unprefixed) name --
# "installed" state is tracked as marker files in $state_dir.
cat >"$test_bin/pacman" <<EOF
#!/bin/bash
if [[ \$1 == "-Q" ]]; then
  [[ -e "$state_dir/\$2" ]] && exit 0
  exit 1
fi
exit 0
EOF
chmod +x "$test_bin/pacman"

# Default yay: "installs" whatever it's given by dropping a marker file for
# each target's bare (unprefixed) name.
write_yay_installs() {
  cat >"$test_bin/yay" <<EOF
#!/bin/bash
echo "yay:\$*" >>"\$TEST_LOG"
for target in "\${@:3}"; do
  touch "$state_dir/\${target#*/}"
done
exit 0
EOF
  chmod +x "$test_bin/yay"
}

# yay that succeeds but installs nothing -- simulates a sync-repo provider
# silently satisfying the transaction instead of the intended AUR package.
write_yay_noop() {
  cat >"$test_bin/yay" <<EOF
#!/bin/bash
echo "yay:\$*" >>"\$TEST_LOG"
exit 0
EOF
  chmod +x "$test_bin/yay"
}

run_aur_add() {
  : >"$log_file"
  rm -f "$state_dir"/*
  PATH="$test_bin:$ROOT/bin:$PATH" TEST_LOG="$log_file" \
    bash "$ROOT/bin/omarchy-pkg-aur-add" "$@"
}

# An "aur/name" target is passed through to yay as-is (to force AUR
# resolution over a same-named sync-repo provider), but the installed-check
# and error reporting use the bare package name pacman actually knows.
write_yay_installs
run_aur_add "aur/voxtype" || fail "aur/-prefixed target succeeds once pacman reports the bare name installed"
grep -qx 'yay:-S --noconfirm --needed aur/voxtype' "$log_file" || fail "yay is invoked with the full aur/name target"
pass "aur/-prefixed target installs and verifies via the bare package name"

# A plain name (no prefix) still works as before.
run_aur_add "jq" || fail "unprefixed target still succeeds"
pass "unprefixed target behaves as before"

# If pacman never reports the bare name as installed, the call fails even
# though yay exited 0 -- guards against a repo provider silently satisfying
# the sync transaction instead of the intended AUR package.
write_yay_noop
if run_aur_add "aur/voxtype"; then
  fail "missing bare package name after install is treated as failure"
fi
pass "missing bare package name after install is treated as failure"
