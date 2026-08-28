#!/bin/bash

set -euo pipefail

# shellcheck source=test/shell.d/base-test.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua
require_command python3

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
next_theme="$home/.local/state/omarchy/current/next-theme"
mkdir -p "$next_theme"

write_colors() {
  cat >"$next_theme/colors.toml" <<'TOML'
mode = "dark"
terminal_opacity = 0.78
terminal_blur = true
terminal_blur_radius = 32
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
}

render() {
  HOME="$home" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-theme-set-templates" 2>"$test_tmp/stderr"
}

reset_theme() {
  rm -rf "$next_theme"
  mkdir -p "$next_theme"
  write_colors
  : >"$test_tmp/stderr"
}

reset_theme
render
grep -qx 'opacity = 0.78' "$next_theme/alacritty.toml" || fail "Alacritty uses terminal opacity"
grep -qx 'blur = true' "$next_theme/alacritty.toml" || fail "Alacritty enables terminal blur"
grep -qx 'alpha=0.78' "$next_theme/foot.ini" || fail "Foot uses terminal opacity"
grep -qx 'blur=yes' "$next_theme/foot.ini" || fail "Foot enables terminal blur"
grep -qx 'background-opacity = 0.78' "$next_theme/ghostty.conf" || fail "Ghostty uses terminal opacity"
grep -qx 'background-blur = 32' "$next_theme/ghostty.conf" || fail "Ghostty uses terminal blur radius"
grep -qx 'background_opacity 0.78' "$next_theme/kitty.conf" || fail "Kitty uses terminal opacity"
grep -qx 'background_blur 32' "$next_theme/kitty.conf" || fail "Kitty uses terminal blur radius"
pass "terminal appearance settings reach every generated terminal config"

reset_theme
sed -i '/^terminal_/d' "$next_theme/colors.toml"
render
grep -qx 'opacity = 1.0' "$next_theme/alacritty.toml" || fail "terminal opacity defaults to opaque"
grep -qx 'blur = false' "$next_theme/alacritty.toml" || fail "Alacritty blur defaults off"
grep -qx 'blur=no' "$next_theme/foot.ini" || fail "Foot blur defaults off"
grep -qx 'background-blur = false' "$next_theme/ghostty.conf" || fail "Ghostty blur defaults off"
grep -qx 'background_blur 0' "$next_theme/kitty.conf" || fail "Kitty blur defaults off"
pass "terminal appearance settings retain safe defaults"

blur_defaults="$test_tmp/blur-defaults.toml"
printf 'terminal_blur = true\n' >"$blur_defaults"
blur_values=$(PATH="$ROOT/bin:$PATH" "$ROOT/bin/omarchy-theme-color" --file "$blur_defaults" --all)
grep -qx $'terminal_blur_radius\t20' <<<"$blur_values" || fail "enabled blur defaults to radius 20"
grep -qx $'terminal_blur_ghostty\t20' <<<"$blur_values" || fail "Ghostty receives the default blur radius"
pass "enabled terminal blur defaults to radius 20"

commented_colors="$test_tmp/commented-colors.toml"
cat >"$commented_colors" <<'TOML'
terminal_opacity = 0.72 # tuned translucency
terminal_blur = true # use compositor blur
terminal_blur_radius = 28 # balanced intensity
TOML
commented_values=$(PATH="$ROOT/bin:$PATH" "$ROOT/bin/omarchy-theme-color" --file "$commented_colors" --all)
grep -qx $'terminal_opacity\t0.72' <<<"$commented_values" || fail "commented opacity resolves"
grep -qx $'terminal_blur\ttrue' <<<"$commented_values" || fail "commented blur resolves"
grep -qx $'terminal_blur_radius\t28' <<<"$commented_values" || fail "commented blur radius resolves"
pass "terminal settings accept TOML inline comments"

invalid_colors="$test_tmp/invalid-colors.toml"
cat >"$invalid_colors" <<'TOML'
terminal_opacity = "1.5"
terminal_blur = "sometimes"
terminal_blur_radius = "1000"
TOML
terminal_values=$(PATH="$ROOT/bin:$PATH" "$ROOT/bin/omarchy-theme-color" --file "$invalid_colors" --all 2>"$test_tmp/invalid-stderr")
grep -qx $'terminal_opacity\t1.0' <<<"$terminal_values" || fail "invalid opacity falls back"
grep -qx $'terminal_blur\tfalse' <<<"$terminal_values" || fail "invalid blur falls back"
grep -qx $'terminal_blur_radius\t0' <<<"$terminal_values" || fail "disabled invalid radius emits zero"
grep -q 'invalid terminal_opacity' "$test_tmp/invalid-stderr" || fail "invalid opacity warns"
grep -q 'invalid terminal_blur ' "$test_tmp/invalid-stderr" || fail "invalid blur warns"
grep -q 'invalid terminal_blur_radius' "$test_tmp/invalid-stderr" || fail "invalid radius warns"
pass "invalid terminal settings warn and fall back"

reset_theme
cat >"$next_theme/hyprland.toml" <<'TOML'
schema = 1

[general]
gaps_in = 4
gaps_out = 9
border_size = 3

[decoration]
rounding = 14
rounding_power = 2.5
active_opacity = 1.0
inactive_opacity = 0.91
fullscreen_opacity = 1.0
dim_inactive = true
dim_strength = 0.08

[decoration.blur]
enabled = true
size = 5
passes = 3
noise = 0.02
contrast = 0.9
brightness = 0.8
vibrancy = 0.15
vibrancy_darkness = 0.7
ignore_opacity = true

[decoration.shadow]
enabled = true
range = 20
render_power = 4
color = "background"
color_inactive = "#11223344"
offset = "-2 3"
scale = 1.0

[group.groupbar]
enabled = true
render_titles = true
scrolling = false
font_size = 12
height = 24
indicator_height = 2
indicator_gap = 5
gaps_in = 4
gaps_out = 1
text_color = "foreground"
text_color_inactive = "#8899aabb"
active_color = "accent"
inactive_color = "background"
gradients = true
gradient_rounding = 6
gradient_round_only_edges = false

[[beziers]]
name = "themeEase"
x1 = 0.25
y1 = 0.46
x2 = 0.45
y2 = 0.94

[[animations]]
name = "windows"
enabled = true
speed = 3.5
curve = "themeEase"
style = "popin 87%"
TOML
render
grep -Fq -- '-- Generated from declarative hyprland.toml' "$next_theme/hyprland.lua" || fail "valid Hyprland declaration is generated"
grep -Fq 'gaps_in = 4' "$next_theme/hyprland.lua" || fail "Hyprland general settings are generated"
grep -Fq 'color = "rgb(1a1b26)"' "$next_theme/hyprland.lua" || fail "Hyprland color resolves a palette reference"
grep -Fq 'color_inactive = "rgba(11223344)"' "$next_theme/hyprland.lua" || fail "Hyprland literal color is normalized"
grep -Fq 'offset = { -2, 3 }' "$next_theme/hyprland.lua" || fail "Hyprland shadow offset is generated as a vector"
grep -Fq 'hl.curve("themeEase"' "$next_theme/hyprland.lua" || fail "Hyprland bezier is generated"
grep -Fq 'leaf = "windows"' "$next_theme/hyprland.lua" || fail "Hyprland animation leaf is generated"
lua - <<LUA
hl = { config = function(_) end, curve = function(_, _) end, animation = function(_) end }
dofile("$next_theme/hyprland.lua")
LUA
pass "valid hyprland.toml generates syntactically valid allowlisted Lua"

reset_theme
render
! grep -Fq 'Generated from declarative hyprland.toml' "$next_theme/hyprland.lua" || fail "absent hyprland.toml changes no generated behavior"
[[ ! -s $test_tmp/stderr ]] || fail "absent hyprland.toml produces no warning" "$(cat "$test_tmp/stderr")"
pass "absent hyprland.toml retains the base Hyprland output"

marker="$test_tmp/pwned"
for invalid_case in unknown malicious malformed schema-type color-form bounds; do
  reset_theme
  case "$invalid_case" in
    unknown)
      printf 'schema = 1\n[general]\nlayout = "master"\n' >"$next_theme/hyprland.toml"
      ;;
    malicious)
      cat >"$next_theme/hyprland.toml" <<TOML
schema = 1
[[animations]]
name = "windows"
enabled = true
style = "fade\"); os.execute(\"touch $marker\") --"
TOML
      ;;
    malformed)
      printf 'schema = 1\n[decoration\nrounding = 4\n' >"$next_theme/hyprland.toml"
      ;;
    schema-type)
      printf 'schema = 1.0\n' >"$next_theme/hyprland.toml"
      ;;
    color-form)
      printf 'schema = 1\n[decoration.shadow]\ncolor = "rgb(11223344)"\n' >"$next_theme/hyprland.toml"
      ;;
    bounds)
      printf 'schema = 1\n[decoration]\nrounding = 21\n' >"$next_theme/hyprland.toml"
      ;;
  esac
  render
  ! grep -Fq 'Generated from declarative hyprland.toml' "$next_theme/hyprland.lua" || fail "$invalid_case Hyprland TOML emits no override"
  grep -q 'ignoring invalid hyprland.toml' "$test_tmp/stderr" || fail "$invalid_case Hyprland TOML warns"
done
[[ ! -e $marker ]] || fail "malicious Hyprland TOML executes nothing"
pass "invalid and malicious hyprland.toml safely fall back to the base output"

reset_theme
printf 'trusted-local-hyprland\n' >"$next_theme/hyprland.lua"
printf 'schema = 1\n[general]\ngaps_in = 99\n' >"$next_theme/hyprland.toml"
render
[[ $(cat "$next_theme/hyprland.lua") == "trusted-local-hyprland" ]] || fail "existing Hyprland Lua remains untouched"
pass "trusted hyprland.lua retains precedence over hyprland.toml"
