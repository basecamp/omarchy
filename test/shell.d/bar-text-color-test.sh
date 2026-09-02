#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command magick

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

export PATH="$ROOT/bin:$PATH"

light_top="$TMPDIR/light-top.png"
dark_top="$TMPDIR/dark-top.png"
dark_band="$TMPDIR/dark-band.png"

magick -size 100x100 xc:'#202020' -fill '#f5f5f5' -draw 'rectangle 0,0 99,19' "$light_top"
magick -size 100x100 xc:'#f5f5f5' -fill '#202020' -draw 'rectangle 0,0 99,19' "$dark_top"
# Light everywhere but the band a bottom bar covers once it is inset by 20.
magick -size 100x100 xc:'#f5f5f5' -fill '#202020' -draw 'rectangle 0,60 99,79' "$dark_band"

result=$(HOME="$TMPDIR" omarchy-bar-text-color top 20 '#ffffff' '#101010' --background "$light_top" --screen 100x100)
[[ $result == "#101010" ]] || fail "transparent bar text switches to background color on light wallpaper" "expected #101010, got $result"
pass "transparent bar text switches to background color on light wallpaper"

result=$(HOME="$TMPDIR" omarchy-bar-text-color top 20 '#ffffff' '#101010' --background "$dark_top" --screen 100x100)
[[ $result == "#ffffff" ]] || fail "transparent bar text keeps text color on dark wallpaper" "expected #ffffff, got $result"
pass "transparent bar text keeps text color on dark wallpaper"

result=$(HOME="$TMPDIR" omarchy-bar-text-color top 20 '#ffffff' '#101010' --background "$TMPDIR/missing.png" --screen 100x100)
[[ $result == "#ffffff" ]] || fail "transparent bar text falls back to text color when sampling fails" "expected #ffffff, got $result"
pass "transparent bar text falls back to text color when sampling fails"

# A detached bar covers a strip the screen edge does not. Same wallpaper, same
# bar size: only the offset moves the sample off the light top band and onto the
# dark one below it, which has to flip the answer.
result=$(HOME="$TMPDIR" omarchy-bar-text-color top 20 '#ffffff' '#101010' --background "$light_top" --screen 100x100 --inset "20 0 0 0")
[[ $result == "#ffffff" ]] || fail "a detached top bar samples the strip it covers" "expected #ffffff, got $result"
pass "a detached top bar samples the strip it covers"

result=$(HOME="$TMPDIR" omarchy-bar-text-color bottom 20 '#ffffff' '#101010' --background "$dark_band" --screen 100x100)
[[ $result == "#101010" ]] || fail "a flush bottom bar samples the screen edge" "expected #101010, got $result"
pass "a flush bottom bar samples the screen edge"

result=$(HOME="$TMPDIR" omarchy-bar-text-color bottom 20 '#ffffff' '#101010' --background "$dark_band" --screen 100x100 --inset "0 0 20 0")
[[ $result == "#ffffff" ]] || fail "a detached bottom bar samples back from its own edge" "expected #ffffff, got $result"
pass "a detached bottom bar samples back from its own edge"

# The gap on the axis the bar spans moves the sample sideways, which is the half
# of a per-edge inset the vertical cases above cannot show.
split="$TMPDIR/split.png"
magick -size 100x100 xc:'#f5f5f5' -fill '#202020' -draw 'rectangle 0,0 49,99' "$split"

result=$(HOME="$TMPDIR" omarchy-bar-text-color top 20 '#ffffff' '#101010' --background "$split" --screen 100x100 --inset "0 0 0 50")
[[ $result == "#101010" ]] || fail "a bar inset from the left samples past the dark half" "expected #101010, got $result"
pass "a bar inset from the left samples past the dark half"

result=$(HOME="$TMPDIR" omarchy-bar-text-color top 20 '#ffffff' '#101010' --background "$split" --screen 100x100 --inset "0 50 0 0")
[[ $result == "#ffffff" ]] || fail "a bar inset from the right stops before the light half" "expected #ffffff, got $result"
pass "a bar inset from the right stops before the light half"
