#!/bin/bash

set -euo pipefail

# migrations/1784401744.sh rewrites ~/.config/tmux/tmux.conf. Declarative setups
# (Nix/home-manager) keep that file read-only or as a symlink into a store.
# A failed write under bash -e must not abort the migration or block
# omarchy-migrate from marking it complete — and must not replace a symlink.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mkdir -p "$test_tmp/bin"
for command in omarchy-restart-tmux omarchy-pkg-missing omarchy-pkg-add omarchy-state omarchy-hw-match lspci; do
  cat >"$test_tmp/bin/$command" <<'SH'
#!/bin/bash
case "$(basename "$0")" in
  omarchy-pkg-missing) exit 1 ;;
  omarchy-hw-match) exit 1 ;;
  lspci) exit 0 ;;
  *) exit 0 ;;
esac
SH
  chmod +x "$test_tmp/bin/$command"
done

# Nix/home-manager shape: symlink to a read-only store object.
home="$test_tmp/home"
store="$test_tmp/nix-store/tmux.conf"
mkdir -p "$home/.config/tmux" "$(dirname "$store")"
cat >"$store" <<'EOF'
# Pane Controls
set -g terminal-features[3] "xterm-kitty:extkeys"
EOF
chmod a-w "$store"
ln -s "$store" "$home/.config/tmux/tmux.conf"
[[ -L $home/.config/tmux/tmux.conf ]] || fail "test setup uses a symlink tmux.conf"
[[ ! -w $home/.config/tmux/tmux.conf ]] || fail "store target must not be writable"

# Before: sed -i under bash -e either fails or replaces the symlink with a file.
broken="$test_tmp/broken.sh"
cat >"$broken" <<'SH'
set -euo pipefail
tmux_config="$HOME/.config/tmux/tmux.conf"
if [[ -f $tmux_config ]]; then
  sed -i 's/^set -g terminal-features\[3\] "xterm-kitty:extkeys"$/set -ag terminal-features "xterm-kitty:extkeys"/' "$tmux_config"
  echo REACHED_AFTER_SED
fi
SH
HOME="$home" bash "$broken" >"$test_tmp/before.out" 2>"$test_tmp/before.err" || true
if [[ -L $home/.config/tmux/tmux.conf ]]; then
  # sed -i failed without replacing the link — that is also the bug path under -e
  if grep -q REACHED_AFTER_SED "$test_tmp/before.out"; then
    fail "sed -i should not report success without rewriting a read-only store target"
  fi
  pass "sed -i on a read-only store symlink does not complete a rewrite"
else
  # GNU sed -i replaced the symlink with a regular file — declarative link lost
  pass "sed -i on a store symlink replaces the link (declarative config broken)"
  # Restore the nix shape for the fixed-migration case.
  rm -f "$home/.config/tmux/tmux.conf"
  chmod u+w "$store" 2>/dev/null || true
  cat >"$store" <<'EOF'
# Pane Controls
set -g terminal-features[3] "xterm-kitty:extkeys"
EOF
  chmod a-w "$store"
  ln -s "$store" "$home/.config/tmux/tmux.conf"
fi

# After: fixed migration completes, leaves the symlink and store content alone.
HOME="$home" PATH="$test_tmp/bin:$PATH" \
  bash -euo pipefail "$ROOT/migrations/1784401744.sh" \
  >"$test_tmp/after.out" 2>"$test_tmp/after.err" ||
  fail "migration must succeed when tmux.conf is not writable" "$(cat "$test_tmp/after.err"; cat "$test_tmp/after.out")"

grep -qi 'skipping tmux.conf' "$test_tmp/after.out" ||
  fail "migration should report that it skipped a non-writable tmux.conf" "$(cat "$test_tmp/after.out")"

[[ -L $home/.config/tmux/tmux.conf ]] ||
  fail "migration must not replace a declarative tmux.conf symlink"
grep -q 'terminal-features\[3\]' "$store" ||
  fail "read-only store content must stay unchanged"
readlink -f "$home/.config/tmux/tmux.conf" | grep -q "$store" ||
  fail "symlink must still point at the store object"
pass "migration skips a non-writable tmux.conf and still completes"

# Writable conf still gets the rewrite; symlink to a writable target is written through.
writable_home="$test_tmp/writable-home"
writable_target="$test_tmp/writable-target.conf"
mkdir -p "$writable_home/.config/tmux"
cat >"$writable_target" <<'EOF'
# Pane Controls
set -g terminal-features[3] "xterm-kitty:extkeys"
EOF
ln -s "$writable_target" "$writable_home/.config/tmux/tmux.conf"

HOME="$writable_home" PATH="$test_tmp/bin:$PATH" \
  bash -euo pipefail "$ROOT/migrations/1784401744.sh" \
  >"$test_tmp/writable.out" 2>"$test_tmp/writable.err" ||
  fail "migration must succeed on a writable tmux.conf" "$(cat "$test_tmp/writable.err")"

[[ -L $writable_home/.config/tmux/tmux.conf ]] ||
  fail "writable symlink tmux.conf must keep pointing at its target"
grep -q 'set -ag terminal-features "xterm-kitty:extkeys"' "$writable_target" ||
  fail "writable tmux.conf should receive the terminal-features rewrite"
grep -q 'M-S-Enter' "$writable_target" ||
  fail "writable tmux.conf should receive the pane control binds"
pass "migration still rewrites a writable tmux.conf through its symlink"
