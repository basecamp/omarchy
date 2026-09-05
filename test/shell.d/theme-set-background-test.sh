#!/bin/bash

set -euo pipefail

# omarchy-theme-set takes the background the theme picker left the user looking
# at. It is matched by name against the backgrounds the theme actually staged --
# the picker points at a theme's own directory, not at the staged copy -- and
# anything the theme does not carry falls back to the usual rotation.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
state="$home/.local/state/omarchy/current"
theme="$home/.config/omarchy/themes/sample"

mkdir -p "$state" "$theme/backgrounds"
printf 'image' >"$theme/backgrounds/1-first.png"
printf 'image' >"$theme/backgrounds/2-second.png"
printf 'preview' >"$theme/preview.png"

cat >"$theme/colors.toml" <<'TOML'
mode = "dark"
background = "#1a1b26"
foreground = "#a9b1d6"
TOML

set_theme() {
  HOME="$home" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
    OMARCHY_THEME_HEADLESS=1 XDG_RUNTIME_DIR="$test_tmp" \
    bash "$ROOT/bin/omarchy-theme-set" "$@" 2>"$test_tmp/stderr"
}

current_background() {
  basename -- "$(readlink "$state/background")"
}

set_theme sample
[[ $(current_background) == "1-first.png" ]] ||
  fail "a theme with no background asked for starts at its first background" "$(current_background)"
pass "theme set falls back to the first background"

set_theme sample "$theme/backgrounds/2-second.png"
[[ $(current_background) == "2-second.png" ]] ||
  fail "theme set applies the background it was handed" "$(current_background)"
[[ $(readlink "$state/background") == "$state/theme/backgrounds/2-second.png" ]] ||
  fail "theme set applies the staged copy of the background it was handed"
pass "theme set applies the background the picker returned"

# What the picker returns when the user never left a theme's preview.
set_theme sample "$theme/preview.png"
[[ $(current_background) == "1-first.png" ]] ||
  fail "an image the theme does not carry rotates instead of pinning" "$(current_background)"
pass "theme set rotates past a background the theme does not carry"

set_theme sample ""
[[ $(current_background) == "2-second.png" ]] ||
  fail "an empty background keeps rotating through the theme" "$(current_background)"
pass "theme set still rotates when handed no background"
