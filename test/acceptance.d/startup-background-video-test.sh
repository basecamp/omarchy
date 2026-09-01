#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_root=$(mktemp -d)
current_background_link="$HOME/.local/state/omarchy/current/background"
original_background=$(readlink -f "$current_background_link" 2>/dev/null || true)
static_background="$test_root/backgrounds/startup-video-test.webp"
startup_directory="$test_root/backgrounds/startup/startup-video-test"
first_frame="$startup_directory/first-frame.webp"
video="$startup_directory/video.mp4"
build_root="$test_root/build"
session_claim="$XDG_RUNTIME_DIR/omarchy-startup-background-video-$HYPRLAND_INSTANCE_SIGNATURE"

restore_background() {
  rmdir "$session_claim" 2>/dev/null || true
  if [[ -n $original_background ]]; then
    ln -sfn "$original_background" "$current_background_link"
    omarchy-shell background setInstant "$original_background" >/dev/null 2>&1 || true
  fi
  rm -rf "$test_root"
}
trap restore_background EXIT

mkdir -p "$startup_directory" "$build_root"
magick -size 1280x720 "xc:#126b33" "$static_background"
magick -size 1280x720 "xc:#b32030" "$first_frame"

# The clip opens on the cover still and closes on the static background, the
# handoff the assets are documented to make. Its middle segment is a colour
# that exists nowhere else in the fixture: the cover still cannot produce it
# and neither can the wallpaper, so capturing blue is the only evidence that a
# frame was really decoded rather than the still fallback sitting on screen.
magick -size 1280x720 "xc:#b32030" "$build_root/open.png"
magick -size 1280x720 "xc:#2038b3" "$build_root/middle.png"
magick -size 1280x720 "xc:#126b33" "$build_root/close.png"

cat >"$build_root/segments.txt" <<SEGMENTS
file '$build_root/open.png'
duration 0.5
file '$build_root/middle.png'
duration 5
file '$build_root/close.png'
duration 1
file '$build_root/close.png'
SEGMENTS

ffmpeg -hide_banner -loglevel error -y \
  -f concat -safe 0 -i "$build_root/segments.txt" \
  -r 30 -an -c:v libx264 -pix_fmt yuv420p "$video"

image_is_blue() {
  [[ $(magick "$1" -resize 1x1\! -colorspace sRGB -format '%[fx:b>r*1.5&&b>g*1.5]' info:) == "1" ]]
}

image_is_green() {
  [[ $(magick "$1" -resize 1x1\! -colorspace sRGB -format '%[fx:g>r*1.5&&g>b*1.5]' info:) == "1" ]]
}

ln -sfn "$static_background" "$current_background_link"
rmdir "$session_claim" 2>/dev/null || true

omarchy-restart-shell
wait_until "shell returns for startup background playback" 30 omarchy-shell shell ping
wait_until "startup background session is claimed" 10 test -d "$session_claim"

# The claim poll lands within a second of the claim itself, so this settles
# inside the clip's blue segment and well clear of both ends of it.
sleep 2

playing_capture="$OMARCHY_ACCEPTANCE_DIR/success-startup-background-video-playing.png"
screenshot "success-startup-background-video-playing"
image_is_blue "$playing_capture" || fail "startup background video decodes and plays" "the playing capture was not predominantly blue, so no video frame reached the screen"
pass "startup background video decodes and plays"

sleep 8
static_capture="$OMARCHY_ACCEPTANCE_DIR/success-startup-background-video-static.png"
screenshot "success-startup-background-video-static"
image_is_green "$static_capture" || fail "startup video hands off to its static background" "the completed capture was not predominantly green"
pass "startup video hands off to its static background"

omarchy-restart-shell
wait_until "shell returns without replaying startup background" 30 omarchy-shell shell ping
sleep 1

restart_capture="$OMARCHY_ACCEPTANCE_DIR/success-startup-background-video-shell-restart.png"
screenshot "success-startup-background-video-shell-restart"
image_is_green "$restart_capture" || fail "shell restart does not replay startup video" "the restart capture did not remain predominantly green"
pass "shell restart does not replay startup video"
