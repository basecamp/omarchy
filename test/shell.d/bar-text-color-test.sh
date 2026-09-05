#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command magick
require_command ffmpeg

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

export PATH="$ROOT/bin:$PATH"

light_top="$TMPDIR/light-top.png"
dark_top="$TMPDIR/dark-top.png"

magick -size 100x100 xc:'#202020' -fill '#f5f5f5' -draw 'rectangle 0,0 99,19' "$light_top"
magick -size 100x100 xc:'#f5f5f5' -fill '#202020' -draw 'rectangle 0,0 99,19' "$dark_top"

result=$(HOME="$TMPDIR" omarchy-bar-text-color top 20 '#ffffff' '#101010' --background "$light_top" --screen 100x100)
[[ $result == "#101010" ]] || fail "transparent bar text switches to background color on light wallpaper" "expected #101010, got $result"
pass "transparent bar text switches to background color on light wallpaper"

result=$(HOME="$TMPDIR" omarchy-bar-text-color top 20 '#ffffff' '#101010' --background "$dark_top" --screen 100x100)
[[ $result == "#ffffff" ]] || fail "transparent bar text keeps text color on dark wallpaper" "expected #ffffff, got $result"
pass "transparent bar text keeps text color on dark wallpaper"

result=$(HOME="$TMPDIR" omarchy-bar-text-color top 20 '#ffffff' '#101010' --background "$TMPDIR/missing.png" --screen 100x100)
[[ $result == "#ffffff" ]] || fail "transparent bar text falls back to text color when sampling fails" "expected #ffffff, got $result"
pass "transparent bar text falls back to text color when sampling fails"

# A video background must be sampled one frame at a time. Reading the whole file
# emits a value per frame, which parses as nothing and silently falls back —
# and decodes the entire wallpaper to find that out.
light_top_video="$TMPDIR/light-top.mp4"
ffmpeg -y -f lavfi -i "testsrc=size=640x360:rate=10:duration=2" \
  -vf "drawbox=x=0:y=0:w=640:h=40:color=0xf5f5f5:t=fill" \
  -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$light_top_video" -loglevel error

result=$(HOME="$TMPDIR" omarchy-bar-text-color top 40 '#ffffff' '#101010' --background "$light_top_video" --screen 640x360)
[[ $result == "#101010" ]] || fail "transparent bar text samples one frame of a video wallpaper" "expected #101010, got $result"
pass "transparent bar text samples one frame of a video wallpaper"
