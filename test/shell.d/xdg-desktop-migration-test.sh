#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration=$(grep -rl 'Move the XDG Desktop target out of the home directory' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "XDG Desktop migration exists"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/xdg-user-dir" <<'SH'
#!/bin/bash
[[ $1 == "DESKTOP" ]]
source "$HOME/.config/user-dirs.dirs"
printf '%s\n' "$XDG_DESKTOP_DIR"
SH

cat >"$mock_bin/xdg-user-dirs-update" <<'SH'
#!/bin/bash
[[ $1 == "--set" && $2 == "DESKTOP" ]]
printf '%s\n' "$*" >>"$TEST_XDG_USER_DIRS_CALLS"
printf 'XDG_DESKTOP_DIR="$HOME/.local/share/desktop"\n' >"$HOME/.config/user-dirs.dirs"
SH
chmod +x "$mock_bin"/*

legacy_home="$test_tmp/legacy-home"
mkdir -p "$legacy_home/.config" "$legacy_home/Desktop"
printf 'XDG_DESKTOP_DIR="$HOME"\n' >"$legacy_home/.config/user-dirs.dirs"
printf 'home shortcut\n' >"$legacy_home/steam.desktop"
printf 'desktop shortcut\n' >"$legacy_home/Desktop/existing.desktop"

calls="$test_tmp/xdg-user-dirs-calls"
HOME="$legacy_home" PATH="$mock_bin:$PATH" TEST_XDG_USER_DIRS_CALLS="$calls" \
  bash -euo pipefail "$migration" >/dev/null

grep -qxF "XDG_DESKTOP_DIR=\"\$HOME/.local/share/desktop\"" "$legacy_home/.config/user-dirs.dirs" ||
  fail "migration moves an exact HOME Desktop target to the hidden directory"
[[ -d $legacy_home/.local/share/desktop ]] ||
  fail "migration creates the hidden Desktop directory"
[[ $(cat "$legacy_home/steam.desktop") == "home shortcut" ]] ||
  fail "migration preserves desktop files already in HOME"
[[ $(cat "$legacy_home/Desktop/existing.desktop") == "desktop shortcut" ]] ||
  fail "migration preserves files in the old Desktop directory"
pass "migration updates only the Desktop target without moving or deleting files"

HOME="$legacy_home" PATH="$mock_bin:$PATH" TEST_XDG_USER_DIRS_CALLS="$calls" \
  bash -euo pipefail "$migration" >/dev/null
[[ $(wc -l <"$calls") -eq 1 ]] || fail "XDG Desktop migration is idempotent"
pass "XDG Desktop migration is idempotent"

custom_home="$test_tmp/custom-home"
mkdir -p "$custom_home/.config"
printf 'XDG_DESKTOP_DIR="$HOME/workspace"\n' >"$custom_home/.config/user-dirs.dirs"

HOME="$custom_home" PATH="$mock_bin:$PATH" TEST_XDG_USER_DIRS_CALLS="$calls" \
  bash -euo pipefail "$migration" >/dev/null

grep -qxF "XDG_DESKTOP_DIR=\"\$HOME/workspace\"" "$custom_home/.config/user-dirs.dirs" ||
  fail "migration preserves a custom XDG Desktop target"
[[ $(wc -l <"$calls") -eq 1 ]] || fail "migration does not rewrite a custom XDG Desktop target"
pass "migration preserves a custom XDG Desktop target"
