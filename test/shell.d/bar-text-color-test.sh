#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command magick

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

export PATH="$ROOT/bin:$PATH"

light_top="$TMPDIR/light-top.png"
dark_top="$TMPDIR/dark-top.png"
split_top="$TMPDIR/split-top.png"

magick -size 100x100 xc:'#202020' -fill '#f5f5f5' -draw 'rectangle 0,0 99,19' "$light_top"
magick -size 100x100 xc:'#f5f5f5' -fill '#202020' -draw 'rectangle 0,0 99,19' "$dark_top"

# Split wallpaper: Left 1/3 light (#f5f5f5), center/right dark (#202020)
magick -size 300x100 xc:'#202020' -fill '#f5f5f5' -draw 'rectangle 0,0 99,19' "$split_top"

# Multi-region default outputs 3 space-separated colors
result=$(HOME="$TMPDIR" omarchy-bar-text-color top 20 '#ffffff' '#101010' --background "$light_top" --screen 100x100)
[[ $result == "#101010 #101010 #101010" ]] || fail "transparent bar text switches to background color across regions on light wallpaper" "expected '#101010 #101010 #101010', got '$result'"
pass "transparent bar text switches to background color across regions on light wallpaper"

result=$(HOME="$TMPDIR" omarchy-bar-text-color top 20 '#ffffff' '#101010' --background "$dark_top" --screen 100x100)
[[ $result == "#ffffff #ffffff #ffffff" ]] || fail "transparent bar text keeps text color across regions on dark wallpaper" "expected '#ffffff #ffffff #ffffff', got '$result'"
pass "transparent bar text keeps text color across regions on dark wallpaper"

# Split wallpaper test
result=$(HOME="$TMPDIR" omarchy-bar-text-color top 20 '#ffffff' '#101010' --background "$split_top" --screen 300x100)
read -r left_col center_col right_col <<< "$result"
[[ $left_col == "#101010" ]] || fail "split wallpaper left region contrast" "expected #101010, got $left_col"
[[ $center_col == "#ffffff" ]] || fail "split wallpaper center region contrast" "expected #ffffff, got $center_col"
[[ $right_col == "#ffffff" ]] || fail "split wallpaper right region contrast" "expected #ffffff, got $right_col"
pass "transparent bar text calculates independent contrast colors per region on split wallpaper"

# Single compatibility mode
result=$(HOME="$TMPDIR" omarchy-bar-text-color top 20 '#ffffff' '#101010' --background "$light_top" --screen 100x100 --single)
[[ $result == "#101010" ]] || fail "transparent bar text supports --single flag" "expected #101010, got $result"
pass "transparent bar text supports --single flag"

# Fallback on missing file
result=$(HOME="$TMPDIR" omarchy-bar-text-color top 20 '#ffffff' '#101010' --background "$TMPDIR/missing.png" --screen 100x100)
[[ $result == "#ffffff #ffffff #ffffff" ]] || fail "transparent bar text falls back to text color when sampling fails" "expected '#ffffff #ffffff #ffffff', got '$result'"
pass "transparent bar text falls back to text color when sampling fails"
