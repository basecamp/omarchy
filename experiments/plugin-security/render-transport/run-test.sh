#!/bin/bash

set -euo pipefail

spike_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
build_dir=${1:-"$spike_dir/build"}
output_dir="$build_dir/frames"

cmake -S "$spike_dir" -B "$build_dir" -G Ninja
cmake --build "$build_dir"

rm -f "$output_dir"/frame-*.png
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none QSG_RHI_BACKEND=software QSG_SOFTWARE_RENDERER_FORCE_PARTIAL_UPDATES=0 "$build_dir/omarchy-plugin-render-spike" "$spike_dir/Scene.qml" "$output_dir"

frame_count=$(find "$output_dir" -maxdepth 1 -type f -name 'frame-*.png' | wc -l)
if (( frame_count != 6 )); then
  echo "expected 6 frames, got $frame_count" >&2
  exit 1
fi

distinct_frames=$(sha256sum "$output_dir"/frame-*.png | awk '{ print $1 }' | sort -u | wc -l)
if (( distinct_frames < 2 )); then
  echo "animation did not produce distinct frames" >&2
  exit 1
fi

if env -u WAYLAND_DISPLAY -u DISPLAY QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none QSG_RHI_BACKEND=software QSG_SOFTWARE_RENDERER_FORCE_PARTIAL_UPDATES=0 "$build_dir/omarchy-plugin-render-spike" "$spike_dir/Scene.qml" "$output_dir/no-display"; then
  echo "rendered without Wayland or X11: $distinct_frames distinct frames"
else
  echo "offscreen rendering failed without Wayland and X11" >&2
  exit 1
fi
