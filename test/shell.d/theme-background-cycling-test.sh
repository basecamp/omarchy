#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_home="$test_tmp/home"
runtime_dir="$test_tmp/runtime"
current_state="$test_home/.local/state/omarchy/current"
mkdir -p "$test_home" "$runtime_dir"

theme="tokyo-night"

set_theme() {
  HOME="$test_home" XDG_RUNTIME_DIR="$runtime_dir" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
    OMARCHY_THEME_HEADLESS=1 "$ROOT/bin/omarchy-theme-set" "$1" >/dev/null
}

current_background() {
  readlink "$current_state/background"
}

# Reapplying the active theme advances to the next background. That lookup
# compares each candidate against the current symlink, so a filename holding
# glob characters has to match itself as a literal string.
set_theme "$theme"

user_backgrounds="$test_home/.config/omarchy/backgrounds/$theme"
mkdir -p "$user_backgrounds"
seed=$(find "$current_state/theme/backgrounds" -maxdepth 1 -type f -print -quit)
[[ -n $seed ]] || fail "test theme ships a background to copy"

glob_background="$user_backgrounds/wall [4k].jpg"
plain_background="$user_backgrounds/wall-plain.jpg"
cp "$seed" "$glob_background"
cp "$seed" "$plain_background"

ln -nsf "$glob_background" "$current_state/background"
set_theme "$theme"
[[ $(current_background) != "$glob_background" ]] ||
  fail "reapplying a theme advances off a background whose name holds glob characters"
pass "reapplying a theme advances off a background whose name holds glob characters"

# A filename without glob characters in the same position, so the test above
# cannot pass merely because cycling is broken for everything.
ln -nsf "$plain_background" "$current_state/background"
set_theme "$theme"
[[ $(current_background) != "$plain_background" ]] ||
  fail "reapplying a theme advances off an ordinary background name"
pass "reapplying a theme advances off an ordinary background name"
