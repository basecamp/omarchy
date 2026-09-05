#!/bin/bash

set -euo pipefail

# A theme installed with `omarchy theme install` often ships only an
# alacritty.toml, so omarchy-theme-colors-from-alacritty derives its colors.toml.
# An alacritty.toml with no [colors.selection] must not end up with a selection
# equal to the foreground: the generated colors.toml is what downstream
# templates read, so a selection that matches the foreground renders every
# highlight as invisible text-on-text.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

generate() {
  local theme="$1"

  bash "$ROOT/bin/omarchy-theme-colors-from-alacritty" "$theme"
}

color_of() {
  local theme="$1" key="$2"

  sed -n "s/^$key = \"\(.*\)\"$/\1/p" "$theme/colors.toml"
}

write_alacritty() {
  local theme="$1"
  mkdir -p "$theme"

  cat >"$theme/alacritty.toml" <<TOML
[colors.primary]
background = "#1a1b26"
foreground = "#c0caf5"

[colors.normal]
black = "#15161e"
red = "#f7768e"
green = "#9ece6a"
yellow = "#e0af68"
blue = "#7aa2f7"
magenta = "#bb9af7"
cyan = "#7dcfff"
white = "#a9b1d6"

[colors.bright]
black = "#414868"
red = "#f7768e"
green = "#9ece6a"
yellow = "#e0af68"
blue = "#7aa2f7"
magenta = "#bb9af7"
cyan = "#7dcfff"
white = "#c0caf5"
TOML
}

assert_color() {
  local theme="$1" key="$2" expected="$3" description="$4"
  local actual
  actual=$(color_of "$theme" "$key")

  [[ $actual == "$expected" ]] || fail "$description" "expected: $expected
actual:   $actual"
  pass "$description"
}

# Without [colors.selection], the selection falls through to color8 rather than
# the foreground.
missing=$test_tmp/missing
write_alacritty "$missing"
generate "$missing"

assert_color "$missing" selection "#414868" \
  "selection falls back to color8 when [colors.selection] is absent"

foreground=$(color_of "$missing" foreground)
[[ $(color_of "$missing" selection) != "$foreground" ]] ||
  fail "selection never equals foreground" "both are $foreground"
pass "selection never equals foreground"

# A theme that does declare a selection background keeps it.
declared=$test_tmp/declared
write_alacritty "$declared"
cat >>"$declared/alacritty.toml" <<'TOML'

[colors.selection]
background = "#283457"
TOML
generate "$declared"

assert_color "$declared" selection "#283457" \
  "a declared [colors.selection] background is preserved"

# Without [colors.bright], color8 falls back to normal black, and the selection
# follows it there rather than to the foreground.
no_bright=$test_tmp/no-bright
mkdir -p "$no_bright"
cat >"$no_bright/alacritty.toml" <<'TOML'
[colors.primary]
background = "#1a1b26"
foreground = "#c0caf5"

[colors.normal]
black = "#15161e"
red = "#f7768e"
green = "#9ece6a"
yellow = "#e0af68"
blue = "#7aa2f7"
magenta = "#bb9af7"
cyan = "#7dcfff"
white = "#a9b1d6"
TOML
generate "$no_bright"

assert_color "$no_bright" selection "#15161e" \
  "selection follows color8 to normal black when [colors.bright] is absent"
