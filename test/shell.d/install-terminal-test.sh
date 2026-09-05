#!/bin/bash

set -euo pipefail

# omarchy-install-terminal must not rewrite xdg-terminals.list or seed config
# when the package never lands (issue #9356). Failure must exit non-zero so
# omarchy-default-terminal --install does not point Super+Return at a missing
# binary.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
home="$test_tmp/home"
omarchy_path="$test_tmp/omarchy"
mkdir -p "$mock_bin" "$home/.config" \
  "$omarchy_path/config/ghostty" \
  "$omarchy_path/config/kitty" \
  "$omarchy_path/config/alacritty" \
  "$omarchy_path/config/foot" \
  "$omarchy_path/default/alacritty" \
  "$omarchy_path/applications"

echo 'ghostty-config' >"$omarchy_path/config/ghostty/config"
echo 'kitty-config' >"$omarchy_path/config/kitty/kitty.conf"
echo 'alacritty-config' >"$omarchy_path/config/alacritty/alacritty.toml"
echo 'foot-config' >"$omarchy_path/config/foot/foot.ini"
printf '[Desktop Entry]\nName=Alacritty\n' >"$omarchy_path/default/alacritty/Alacritty.desktop"
printf '[Desktop Entry]\nName=Foot\n' >"$omarchy_path/applications/foot.desktop"

# Pre-existing default terminal the failure path must leave alone.
cat >"$home/.config/xdg-terminals.list" <<'EOF'
# Terminal emulator preference order for xdg-terminal-exec
kitty.desktop
EOF
original_list=$(cat "$home/.config/xdg-terminals.list")

cat >"$mock_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'pkg-add %s\n' "$*" >>"$OMARCHY_INSTALL_TERMINAL_LOG"
if [[ ${OMARCHY_PKG_ADD_EXIT:-1} -eq 0 ]]; then
  exit 0
fi
echo "Error: Package '$1' did not install" >&2
exit "${OMARCHY_PKG_ADD_EXIT:-1}"
SH

cat >"$mock_bin/omarchy-pkg-present" <<'SH'
#!/bin/bash
if [[ -f $OMARCHY_INSTALLED_DIR/$1 ]]; then
  exit 0
fi
exit 1
SH

chmod +x "$mock_bin"/*

export HOME="$home"
export OMARCHY_PATH="$omarchy_path"
export OMARCHY_INSTALL_TERMINAL_LOG="$test_tmp/log"
export OMARCHY_INSTALLED_DIR="$test_tmp/installed"
export OMARCHY_PKG_ADD_EXIT=1
export PATH="$mock_bin:$PATH"
mkdir -p "$OMARCHY_INSTALLED_DIR"
: >"$OMARCHY_INSTALL_TERMINAL_LOG"

installer="$ROOT/bin/omarchy-install-terminal"

# --- Failure: pkg-add exits non-zero ------------------------------------------
export OMARCHY_PKG_ADD_EXIT=1
if HOME="$home" "$installer" ghostty >"$test_tmp/fail.out" 2>"$test_tmp/fail.err"; then
  fail "install-terminal must exit non-zero when pkg-add fails" "$(cat "$test_tmp/fail.out"; cat "$test_tmp/fail.err")"
fi
grep -Fq 'Failed to install ghostty' "$test_tmp/fail.err" ||
  fail "install-terminal reports the failure on stderr" "$(cat "$test_tmp/fail.err")"
[[ $(cat "$home/.config/xdg-terminals.list") == "$original_list" ]] ||
  fail "failed install must not rewrite xdg-terminals.list" "$(cat "$home/.config/xdg-terminals.list")"
[[ ! -e $home/.config/ghostty ]] ||
  fail "failed install must not seed ~/.config/ghostty"
grep -qx 'pkg-add ghostty' "$OMARCHY_INSTALL_TERMINAL_LOG" ||
  fail "failed install still attempted pkg-add"
pass "pkg-add failure leaves defaults and config untouched and exits non-zero"

# --- Failure: pkg-add exits 0 but package never present (issue #9356 shape) ---
: >"$OMARCHY_INSTALL_TERMINAL_LOG"
export OMARCHY_PKG_ADD_EXIT=0
if HOME="$home" "$installer" ghostty >"$test_tmp/lie.out" 2>"$test_tmp/lie.err"; then
  fail "install-terminal must exit non-zero when pkg-add succeeds without the package" "$(cat "$test_tmp/lie.out"; cat "$test_tmp/lie.err")"
fi
grep -Fq 'Failed to install ghostty' "$test_tmp/lie.err" ||
  fail "missing package after pkg-add is reported as failure" "$(cat "$test_tmp/lie.err")"
[[ $(cat "$home/.config/xdg-terminals.list") == "$original_list" ]] ||
  fail "lying pkg-add must not rewrite xdg-terminals.list" "$(cat "$home/.config/xdg-terminals.list")"
[[ ! -e $home/.config/ghostty ]] ||
  fail "lying pkg-add must not seed ~/.config/ghostty"
pass "pkg-add exit 0 without package present does not mutate terminal defaults"

# --- Success path -------------------------------------------------------------
: >"$OMARCHY_INSTALL_TERMINAL_LOG"
export OMARCHY_PKG_ADD_EXIT=0
touch "$OMARCHY_INSTALLED_DIR/ghostty"
HOME="$home" "$installer" ghostty >"$test_tmp/ok.out" 2>"$test_tmp/ok.err" ||
  fail "successful install must exit 0" "$(cat "$test_tmp/ok.out"; cat "$test_tmp/ok.err")"
[[ $(tail -n 1 "$home/.config/xdg-terminals.list") == "com.mitchellh.ghostty.desktop" ]] ||
  fail "successful install sets the ghostty desktop id" "$(cat "$home/.config/xdg-terminals.list")"
[[ -f $home/.config/ghostty/config ]] ||
  fail "successful install seeds the ghostty config"
grep -qx 'ghostty-config' "$home/.config/ghostty/config" ||
  fail "seeded ghostty config matches the packaged default"
pass "successful install rewrites the default terminal and seeds config"

# --- Idempotent config seed ---------------------------------------------------
echo 'user-custom' >"$home/.config/ghostty/config"
touch "$OMARCHY_INSTALLED_DIR/ghostty"
HOME="$home" "$installer" ghostty >/dev/null 2>&1 ||
  fail "re-install with existing config must succeed"
grep -qx 'user-custom' "$home/.config/ghostty/config" ||
  fail "existing terminal config must not be overwritten"
pass "existing terminal config is left alone on re-install"

# --- Unknown terminal ---------------------------------------------------------
if HOME="$home" "$installer" not-a-term >"$test_tmp/unknown.out" 2>"$test_tmp/unknown.err"; then
  fail "unknown terminal must exit non-zero"
fi
grep -Fq 'Unknown terminal' "$test_tmp/unknown.err" ||
  fail "unknown terminal is reported" "$(cat "$test_tmp/unknown.err")"
pass "unknown terminal is rejected"

# --- default-terminal cascade: failed install must not rewrite list ----------
cp "$ROOT/bin/omarchy-default-terminal" "$mock_bin/omarchy-default-terminal"
cp "$ROOT/bin/omarchy-install-terminal" "$mock_bin/omarchy-install-terminal"
chmod +x "$mock_bin/omarchy-default-terminal" "$mock_bin/omarchy-install-terminal"

cat >"$mock_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
: # no-op
SH
cat >"$mock_bin/omarchy-launch-floating-terminal-with-presentation" <<'SH'
#!/bin/bash
eval "$*"
SH
chmod +x "$mock_bin/omarchy-cmd-missing" "$mock_bin/omarchy-notification-send" \
  "$mock_bin/omarchy-launch-floating-terminal-with-presentation"

# Reset defaults to kitty; package still absent.
cat >"$home/.config/xdg-terminals.list" <<'EOF'
# Terminal emulator preference order for xdg-terminal-exec
kitty.desktop
EOF
rm -f "$OMARCHY_INSTALLED_DIR/ghostty"
export OMARCHY_PKG_ADD_EXIT=1

if HOME="$home" OMARCHY_PATH="$omarchy_path" PATH="$mock_bin:$PATH" \
  omarchy-default-terminal --install ghostty >"$test_tmp/cascade.out" 2>"$test_tmp/cascade.err"; then
  fail "default-terminal --install must fail when the package never lands" "$(cat "$test_tmp/cascade.out"; cat "$test_tmp/cascade.err")"
fi
[[ $(tail -n 1 "$home/.config/xdg-terminals.list") == "kitty.desktop" ]] ||
  fail "failed default-terminal install must keep the previous default" "$(cat "$home/.config/xdg-terminals.list")"
pass "default-terminal --install preserves the previous default when install fails"
