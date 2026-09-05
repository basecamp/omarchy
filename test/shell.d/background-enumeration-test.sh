#!/bin/bash

set -euo pipefail

# Background enumeration treats aspect-ratio variants (<stem>@<label>.<ext>) as
# render-time data, never as entries of their own: cyclers and pickers list only
# canonical files, SVG backgrounds are first-class entries, and the state
# symlink never points at a variant.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command magick
require_command jq

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stubs="$test_tmp/stubs"
mkdir -p "$stubs"

cat >"$stubs/omarchy-shell" <<'STUB'
#!/bin/bash
exit 0
STUB
cat >"$stubs/omarchy-notification-send" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$stubs"/*

write_fixture_backgrounds() {
  local dir="$1"

  mkdir -p "$dir"
  magick -size 4x2 xc:red "$dir/1-a.png"
  magick -size 8x2 xc:blue "$dir/1-a@ultrawide.png"
  cat >"$dir/2-b.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"><rect width="4" height="4" fill="#00ff00"/></svg>
SVG
}

# omarchy-theme-bg-next cycles over canonical files only, including SVG.
home_next="$test_tmp/home-next"
state_next="$home_next/.local/state/omarchy/current"
mkdir -p "$state_next"
printf 'bgtest\n' >"$state_next/theme.name"
write_fixture_backgrounds "$state_next/theme/backgrounds"

bg_next() {
  HOME="$home_next" PATH="$stubs:$ROOT/bin:$PATH" OMARCHY_PATH="$ROOT" \
    bash "$ROOT/bin/omarchy-theme-bg-next"
}

current_background_name() {
  local link="$1"
  local target

  target=$(readlink "$link") || fail "the current background symlink exists"
  printf '%s' "${target##*/}"
}

bg_next || fail "omarchy-theme-bg-next runs against the fixture state"
[[ $(current_background_name "$state_next/background") == "1-a.png" ]] ||
  fail "omarchy-theme-bg-next starts the cycle at the first canonical file"

bg_next || fail "omarchy-theme-bg-next advances the cycle"
[[ $(current_background_name "$state_next/background") == "2-b.svg" ]] ||
  fail "omarchy-theme-bg-next includes SVG backgrounds and skips variants"

bg_next || fail "omarchy-theme-bg-next wraps the cycle"
[[ $(current_background_name "$state_next/background") == "1-a.png" ]] ||
  fail "omarchy-theme-bg-next wraps back to the first canonical file"

pass "omarchy-theme-bg-next cycles over canonical files and SVGs, never variants"

# The theme-set background chooser never links a variant either.
home_set="$test_tmp/home-set"
state_set="$home_set/.local/state/omarchy/current"
themes_set="$home_set/.config/omarchy/themes"
mkdir -p "$state_set" "$themes_set/bgtest"
write_fixture_backgrounds "$themes_set/bgtest/backgrounds"

cat >"$themes_set/bgtest/colors.toml" <<'TOML'
accent = "#7aa2f7"
selection = "#292e42"
muted = "#414868"

background = "#1a1b26"
foreground = "#a9b1d6"

color0 = "#1a1b26"
color1 = "#f7768e"
color2 = "#9ece6a"
color3 = "#e0af68"
color4 = "#7aa2f7"
color5 = "#bb9af7"
color6 = "#7dcfff"
color7 = "#a9b1d6"
TOML

set_theme() {
  HOME="$home_set" OMARCHY_PATH="$ROOT" PATH="$stubs:$ROOT/bin:$PATH" \
    OMARCHY_THEME_HEADLESS=1 XDG_RUNTIME_DIR="$test_tmp" \
    bash "$ROOT/bin/omarchy-theme-set" bgtest 2>"$test_tmp/stderr" || return $?
}

for expected in 1-a.png 2-b.svg 1-a.png; do
  set_theme || fail "omarchy-theme-set applies the fixture theme headlessly" "$(cat "$test_tmp/stderr")"
  chosen=$(current_background_name "$state_set/background")
  [[ $chosen != *@* ]] || fail "the theme-set chooser never links a variant"
  [[ $chosen == "$expected" ]] ||
    fail "the theme-set chooser cycles canonical files including SVG" "expected: $expected, chosen: $chosen"
done

pass "the theme-set chooser cycles canonical files and never links a variant"

# The image picker list feed applies the same whitelist.
list_rows=$(HOME="$home_next" bash "$ROOT/shell/plugins/image-picker/list.sh" "$state_next/theme/backgrounds")
grep -q '1-a\.png' <<<"$list_rows" || fail "list.sh lists canonical raster backgrounds"
grep -q '2-b\.svg' <<<"$list_rows" || fail "list.sh lists SVG backgrounds"
! grep -q '@ultrawide' <<<"$list_rows" || fail "list.sh excludes aspect-ratio variants"

pass "the image picker list feed matches the enumeration whitelist"

# omarchy-theme-bg-current strips a variant label when it shows one defensively.
ln -nsf "$state_next/theme/backgrounds/1-a@ultrawide.png" "$state_next/background"
name=$(HOME="$home_next" bash "$ROOT/bin/omarchy-theme-bg-current")
[[ $name == "A" ]] || fail "omarchy-theme-bg-current strips the variant label" "got: $name"

pass "omarchy-theme-bg-current prints a variant path cleanly"

# omarchy-bar-text-color samples the path the resolver picks and honors its
# fill metadata; a failing resolver falls back to the state symlink.
magick -size 8x8 xc:white "$test_tmp/white.png"
magick -size 8x8 xc:black "$test_tmp/black.png"
magick -size 1x1 xc:black "$test_tmp/dot.png"

resolver_fields() {
  local path="$1"
  local fill="$2"
  local fill_color="$3"

  cat >"$stubs/omarchy-theme-bg-resolve" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >"$test_tmp/resolver-args"
printf 'path\t%s\n' "$path"
printf 'canonical\t%s\n' "$path"
printf 'fill\t%s\n' "$fill"
printf 'fill_color\t%s\n' "$fill_color"
printf 'focal_x\t0.5\nfocal_y\t0.5\n'
STUB
  chmod +x "$stubs/omarchy-theme-bg-resolve"
}

bar_text_color() {
  HOME="$home_next" PATH="$stubs:$ROOT/bin:$PATH" \
    bash "$ROOT/bin/omarchy-bar-text-color" top 2 '#ffffff' '#000000' --screen 8x8
}

resolver_fields "$test_tmp/white.png" crop '#ffffff'
[[ $(bar_text_color) == "#000000" ]] ||
  fail "omarchy-bar-text-color samples the resolver's path in crop mode"

resolver_fields "$test_tmp/dot.png" center '#ffffff'
[[ $(bar_text_color) == "#000000" ]] ||
  fail "omarchy-bar-text-color composites center fills over the fill color"

resolver_fields "$test_tmp/black.png" fit '#000000'
[[ $(bar_text_color) == "#ffffff" ]] ||
  fail "omarchy-bar-text-color composites fit fills over the fill color"

resolver_fields "$test_tmp/white.png" tile '#ffffff'
[[ $(bar_text_color) == "#000000" ]] ||
  fail "omarchy-bar-text-color tiles the resolved image"

# The shell paints fill_color under tiles too: a transparent tile over a white
# fill must sample white, not the transparent pixels' black.
magick -size 4x4 xc:none "$test_tmp/transparent.png"
resolver_fields "$test_tmp/transparent.png" tile '#ffffff'
[[ $(bar_text_color) == "#000000" ]] ||
  fail "omarchy-bar-text-color composites tile fills over the fill color"

# A rotated monitor (odd transform) reports its raw mode resolution through
# hyprctl; the derived --screen must use the swapped, logical dimensions.
cat >"$stubs/hyprctl" <<'STUB'
#!/bin/bash
printf '[{"width":2560,"height":1440,"transform":1}]\n'
STUB
chmod +x "$stubs/hyprctl"

resolver_fields "$test_tmp/white.png" crop '#ffffff'
rotated=$(HOME="$home_next" PATH="$stubs:$ROOT/bin:$PATH" \
  bash "$ROOT/bin/omarchy-bar-text-color" top 2 '#ffffff' '#000000')
[[ $rotated == "#000000" ]] ||
  fail "omarchy-bar-text-color samples with the hyprctl-derived screen size"
grep -q -- '--screen 1440x2560' "$test_tmp/resolver-args" ||
  fail "omarchy-bar-text-color swaps width/height for odd monitor transforms" "$(cat "$test_tmp/resolver-args")"

cat >"$stubs/omarchy-theme-bg-resolve" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod +x "$stubs/omarchy-theme-bg-resolve"

ln -nsf "$test_tmp/black.png" "$state_next/background"
[[ $(bar_text_color) == "#ffffff" ]] ||
  fail "omarchy-bar-text-color falls back to the state symlink when the resolver fails"

pass "omarchy-bar-text-color follows the resolver and keeps its fallback"
