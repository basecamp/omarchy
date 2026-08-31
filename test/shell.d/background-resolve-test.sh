#!/bin/bash

set -euo pipefail

# omarchy-theme-bg-resolve is the single implementation of background
# resolution: aspect-ratio variant selection per screen, render metadata from
# backgrounds.toml, and per-screen SVG rasterization. These tests drive it
# against a fake HOME so the real user state is never touched.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command magick
require_command rsvg-convert
require_command jq

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
state="$home/.local/state/omarchy/current"
backgrounds="$state/theme/backgrounds"
mkdir -p "$backgrounds"

resolve() {
  HOME="$home" PATH="$ROOT/bin:$PATH" bash "$ROOT/bin/omarchy-theme-bg-resolve" "$@"
}

fields_value() {
  awk -F '\t' -v key="$1" '$1 == key { print $2 }' <<<"$2"
}

# Without a current background there is nothing to resolve.
if resolve --fields >/dev/null 2>&1; then
  fail "the resolver exits nonzero when no current background exists"
fi

pass "the resolver exits nonzero when no current background exists"

# A two-argument option with its value missing must fail fast: the argument
# loop once spun forever because shift 2 shifts nothing when only the flag
# remains (timeout rc 124 means the hang is back).
for flag in --screen --canonical; do
  rc=0
  HOME="$home" timeout 2 bash "$ROOT/bin/omarchy-theme-bg-resolve" "$flag" >/dev/null 2>&1 || rc=$?
  (( rc != 0 && rc != 124 )) || fail "$flag without a value fails fast" "rc=$rc"
done

pass "a two-argument option missing its value exits nonzero without hanging"

# No backgrounds.toml, no variants, no --screen: the canonical file with the
# built-in defaults, and black because no theme palette resolves.
magick -size 160x90 xc:red "$backgrounds/1-base.png"
ln -nsf "$backgrounds/1-base.png" "$state/background"
base=$(realpath "$backgrounds/1-base.png")

output=$(resolve --fields)
[[ $(fields_value path "$output") == "$base" ]] || fail "the canonical file resolves to itself" "$output"
[[ $(fields_value canonical "$output") == "$base" ]] || fail "the canonical field names the canonical file" "$output"
[[ $(fields_value fill "$output") == "crop" ]] || fail "fill defaults to crop" "$output"
[[ $(fields_value fill_color "$output") == "#000000" ]] || fail "fill_color falls back to black without a palette" "$output"
[[ $(fields_value focal_x "$output") == "0.5" ]] || fail "focal_x defaults to 0.5" "$output"
[[ $(fields_value focal_y "$output") == "0.5" ]] || fail "focal_y defaults to 0.5" "$output"

pass "no metadata and no variants resolve to the canonical file with defaults"

# Variant selection: a 32:9 screen picks the ultrawide variant, a 16:9 screen
# keeps the base, and without --screen the canonical file always wins.
magick -size 1600x900 xc:red "$backgrounds/2-scene.png"
magick -size 3200x900 xc:blue "$backgrounds/2-scene@ultrawide.png"
ln -nsf "$backgrounds/2-scene.png" "$state/background"
scene=$(realpath "$backgrounds/2-scene.png")
scene_ultrawide=$(realpath "$backgrounds/2-scene@ultrawide.png")

output=$(resolve --fields --screen 5120x1440)
[[ $(fields_value path "$output") == "$scene_ultrawide" ]] || fail "a 5120x1440 screen picks the ultrawide variant" "$output"
[[ $(fields_value canonical "$output") == "$scene" ]] || fail "the canonical field stays on the base file" "$output"

output=$(resolve --fields --screen 1920x1080)
[[ $(fields_value path "$output") == "$scene" ]] || fail "a 1920x1080 screen keeps the base image" "$output"

output=$(resolve --fields)
[[ $(fields_value path "$output") == "$scene" ]] || fail "without --screen the canonical file is selected" "$output"

pass "the variant closest to the screen aspect is selected per screen"

# backgrounds.toml: [defaults] applies to every image, a quoted per-stem
# section overrides it, and fill_color takes hex or a theme palette key.
cat >"$state/theme/colors.toml" <<'TOML'
accent = "#7aa2f7"

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

cat >"$backgrounds/backgrounds.toml" <<'TOML'
[defaults]
fill = "fit"
fill_color = "#123456"

["3-meadow"]
fill = "center"
fill_color = "accent"
focal = "0.65 0.4"
TOML

magick -size 160x90 xc:green "$backgrounds/3-meadow.png"
magick -size 160x90 xc:gray "$backgrounds/4-plain.png"
ln -nsf "$backgrounds/3-meadow.png" "$state/background"

output=$(resolve --fields)
[[ $(fields_value fill "$output") == "center" ]] || fail "a per-stem section overrides the default fill" "$output"
[[ $(fields_value fill_color "$output") == "#7aa2f7" ]] || fail "a palette-key fill_color resolves through the theme palette" "$output"
[[ $(fields_value focal_x "$output") == "0.65" ]] || fail "a per-stem focal_x is honored" "$output"
[[ $(fields_value focal_y "$output") == "0.4" ]] || fail "a per-stem focal_y is honored" "$output"

output=$(resolve --fields --canonical "$backgrounds/4-plain.png")
[[ $(fields_value path "$output") == "$(realpath "$backgrounds/4-plain.png")" ]] || fail "--canonical overrides the state symlink" "$output"
[[ $(fields_value fill "$output") == "fit" ]] || fail "an image without a section gets the [defaults] fill" "$output"
[[ $(fields_value fill_color "$output") == "#123456" ]] || fail "a hex fill_color passes through unresolved" "$output"
[[ $(fields_value focal_x "$output") == "0.5" ]] || fail "focal stays at the default without an override" "$output"

pass "backgrounds.toml defaults and per-stem overrides resolve fill, fill_color, and focal"

# An SVG selected for a known screen rasterizes to a cached PNG covering the
# screen; the same request reuses the cache, and no --screen keeps the SVG.
cat >>"$backgrounds/backgrounds.toml" <<'TOML'

["5-art"]
fill = "crop"
TOML

cat >"$backgrounds/5-art.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50"><rect width="100" height="50" fill="#ff0000"/></svg>
SVG
ln -nsf "$backgrounds/5-art.svg" "$state/background"
art=$(realpath "$backgrounds/5-art.svg")

output=$(resolve --fields --screen 200x200)
rendered=$(fields_value path "$output")
[[ $rendered == "$home/.cache/omarchy/background-renders/"*.png ]] || fail "an SVG resolves to a cached PNG render" "$output"
[[ -f $rendered ]] || fail "the rasterized PNG exists" "$output"
[[ $(fields_value canonical "$output") == "$art" ]] || fail "the canonical field stays on the SVG" "$output"

dims=$(magick identify -ping -format '%wx%h' "$rendered")
[[ $dims == "400x200" ]] || fail "the crop render covers a 200x200 screen from a 100x50 SVG" "got $dims"

output=$(resolve --fields --screen 200x200)
[[ $(fields_value path "$output") == "$rendered" ]] || fail "an identical request reuses the cached render" "$output"

output=$(resolve --fields)
[[ $(fields_value path "$output") == "$art" ]] || fail "without --screen the SVG path is returned unchanged" "$output"

pass "SVG backgrounds rasterize to cached cover-sized PNGs per screen"

# Malformed metadata never breaks resolution: unparseable lines are ignored
# and invalid values fall back to the defaults (with the theme background
# color backing an unknown palette key).
cat >"$backgrounds/backgrounds.toml" <<'TOML'
this is not toml
]]] broken
[defaults
[defaults]
fill = "diagonal"
focal = "2 9"
fill_color = "not-a-real-key"
TOML
ln -nsf "$backgrounds/4-plain.png" "$state/background"

output=$(resolve --fields)
[[ $(fields_value path "$output") == "$(realpath "$backgrounds/4-plain.png")" ]] || fail "malformed metadata still resolves the canonical file" "$output"
[[ $(fields_value fill "$output") == "crop" ]] || fail "an invalid fill falls back to crop" "$output"
[[ $(fields_value fill_color "$output") == "#1a1b26" ]] || fail "an unknown palette key falls back to the theme background" "$output"
[[ $(fields_value focal_x "$output") == "0.5" ]] || fail "an out-of-range focal falls back to 0.5" "$output"
[[ $(fields_value focal_y "$output") == "0.5" ]] || fail "an out-of-range focal falls back to 0.5" "$output"

pass "malformed backgrounds.toml falls back to the defaults"

# Output shapes: --fields prints exactly the six keys in order, and the JSON
# object carries the same values with paths escaped well enough for jq.
keys=$(resolve --fields | cut -f1 | paste -sd,)
[[ $keys == "path,canonical,fill,fill_color,focal_x,focal_y" ]] || fail "--fields prints exactly the six documented keys" "$keys"

magick -size 160x90 xc:blue "$backgrounds/6-quo\"te.png"
ln -nsf "$backgrounds/6-quo\"te.png" "$state/background"
quoted=$(realpath "$backgrounds/6-quo\"te.png")

json=$(resolve)
jq -e --arg path "$quoted" '
  .path == $path and .canonical == $path and .fill == "crop" and
  .focal_x == 0.5 and .focal_y == 0.5 and (.fill_color | type) == "string"
' <<<"$json" >/dev/null || fail "the JSON output parses and escapes paths" "$json"

pass "--fields and JSON outputs share the same shape"

# A [-led line that fails the section-header pattern still ends the previous
# section: its keys are inert instead of leaking into the section above, and
# the image it meant to configure just gets the defaults.
cat >"$backgrounds/backgrounds.toml" <<'TOML'
["7-alpha"]
fill = "fit"

["br]oken"]
fill = "tile"
focal = "0.9 0.9"

["7-beta"]
fill = "fit"

[[7-array]]
fill = "tile"
focal = "0.9 0.9"

["7-gamma"]
fill = "fit"

[7-gamma] trailing junk
fill = "tile"
focal = "0.9 0.9"
TOML

for stem in 7-alpha 7-beta 7-gamma; do
  magick -size 160x90 xc:red "$backgrounds/$stem.png"
  output=$(resolve --fields --canonical "$backgrounds/$stem.png")
  [[ $(fields_value fill "$output") == "fit" ]] || fail "keys after a broken header do not leak into [$stem]" "$output"
  [[ $(fields_value focal_x "$output") == "0.5" ]] || fail "focal after a broken header does not leak into [$stem]" "$output"
done

magick -size 160x90 xc:red "$backgrounds/7-array.png"
output=$(resolve --fields --canonical "$backgrounds/7-array.png")
[[ $(fields_value fill "$output") == "crop" ]] || fail "an array-of-tables header is inert and its image falls back to the defaults" "$output"

pass "broken section headers end the previous section without leaking keys"

# fill_color hardening: an option-shaped value never reaches omarchy-theme-color
# as an argument, and a malformed hex value is rejected; both fall back to the
# theme background color.
cat >"$backgrounds/backgrounds.toml" <<'TOML'
["8-inject"]
fill_color = "--file"

["8-badhex"]
fill_color = "#zzzzzz"
TOML

magick -size 160x90 xc:red "$backgrounds/8-inject.png"
magick -size 160x90 xc:red "$backgrounds/8-badhex.png"

output=$(resolve --fields --canonical "$backgrounds/8-inject.png")
[[ $(fields_value fill_color "$output") == "#1a1b26" ]] || fail "an option-shaped fill_color falls back to the theme background" "$output"

output=$(resolve --fields --canonical "$backgrounds/8-badhex.png")
[[ $(fields_value fill_color "$output") == "#1a1b26" ]] || fail "a malformed hex fill_color falls back to the theme background" "$output"

pass "unsafe fill_color values fall back to the theme background"

# Control characters in an emitted string cannot corrupt the framing: a path
# with an embedded newline still yields exactly six field lines and valid JSON.
nl_name="$backgrounds/9-line"$'\n'"break.png"
magick -size 160x90 xc:red "$nl_name"

output=$(resolve --fields --canonical "$nl_name")
lines=$(wc -l <<<"$output")
(( lines == 6 )) || fail "a newline in the path cannot add field lines" "$output"
[[ $(fields_value path "$output") == *"/9-linebreak.png" ]] || fail "the control character is stripped from the emitted path" "$output"

json=$(resolve --canonical "$nl_name")
jq -e '.path | endswith("/9-linebreak.png")' <<<"$json" >/dev/null || fail "JSON output stays parseable with a control character in the path" "$json"

pass "control characters never corrupt the output framing"
