#!/bin/bash

set -euo pipefail

# omarchy-theme-colors-from-alacritty fills selection when alacritty.toml has no
# [colors.selection] block. That value is written into colors.toml and then
# wins over omarchy-theme-color's own fallback chain, so a bad default here
# paints every {{ selection }} consumer with invisible text-on-text highlights.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

theme="$test_tmp/theme"
mkdir -p "$theme"

# A minimal alacritty palette with no [colors.selection] section.
cat >"$theme/alacritty.toml" <<'TOML'
[colors.primary]
background = "#1e1e2e"
foreground = "#cdd6f4"

[colors.normal]
black = "#1e1e2e"
red = "#f38ba8"
green = "#a6e3a1"
yellow = "#f9e2af"
blue = "#89b4fa"
magenta = "#cba6f7"
cyan = "#94e2d5"
white = "#cdd6f4"

[colors.bright]
black = "#585b70"
red = "#f38ba8"
green = "#a6e3a1"
yellow = "#f9e2af"
blue = "#89b4fa"
magenta = "#cba6f7"
cyan = "#94e2d5"
white = "#cdd6f4"
TOML

bash "$ROOT/bin/omarchy-theme-colors-from-alacritty" "$theme" \
  || fail "omarchy-theme-colors-from-alacritty generates colors.toml from alacritty.toml"

[[ -f $theme/colors.toml ]] || fail "colors.toml is written beside alacritty.toml"

selection=$(awk -F'"' '/^selection[[:space:]]*=/{print $2; exit}' "$theme/colors.toml")
foreground=$(awk -F'"' '/^foreground[[:space:]]*=/{print $2; exit}' "$theme/colors.toml")
color8=$(awk -F'"' '/^color8[[:space:]]*=/{print $2; exit}' "$theme/colors.toml")

[[ -n $selection && -n $foreground && -n $color8 ]] \
  || fail "generated colors.toml carries selection, foreground, and color8" \
    "selection=$selection foreground=$foreground color8=$color8"

[[ $selection != "$foreground" ]] \
  || fail "selection does not fall back to the foreground text color" \
    "selection=$selection foreground=$foreground"

[[ $selection == "$color8" ]] \
  || fail "selection falls back through color8 when [colors.selection] is absent" \
    "selection=$selection color8=$color8"

pass "missing [colors.selection] falls back to color8, not foreground"

# An explicit selection background still wins over the cascade.
rm -f "$theme/colors.toml"
cat >>"$theme/alacritty.toml" <<'TOML'

[colors.selection]
background = "#45475a"
TOML

bash "$ROOT/bin/omarchy-theme-colors-from-alacritty" "$theme" \
  || fail "omarchy-theme-colors-from-alacritty regenerates when colors.toml is absent"

selection=$(awk -F'"' '/^selection[[:space:]]*=/{print $2; exit}' "$theme/colors.toml")
[[ $selection == "#45475a" ]] \
  || fail "an explicit [colors.selection].background is preserved" \
    "selection=$selection"

pass "explicit [colors.selection].background is preserved"
