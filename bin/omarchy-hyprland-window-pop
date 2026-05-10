#!/bin/bash

# omarchy:summary=Toggle to pop-out a tile to stay fixed on a display basis.
# omarchy:args=[width height x y]

width=${1:-1300}
height=${2:-900}
x=${3:-}
y=${4:-}

active=$(hyprctl activewindow -j)
pinned=$(echo "$active" | jq ".pinned")
addr=$(echo "$active" | jq -r ".address")
window="address:$addr"

hypr_dispatch() {
  local lua="$1"
  shift

  hyprctl dispatch "$lua" >/dev/null 2>&1 || hyprctl dispatch "$@" >/dev/null
}

if [[ $pinned == "true" ]]; then
  hypr_dispatch "hl.dsp.window.pin({ window = \"$window\" })" pin "$window"
  hypr_dispatch "hl.dsp.window.float({ window = \"$window\", action = \"toggle\" })" togglefloating "$window"
  hypr_dispatch "hl.dsp.window.tag({ window = \"$window\", tag = \"-pop\" })" tagwindow -pop "$window"
elif [[ -n $addr ]]; then
  hypr_dispatch "hl.dsp.window.float({ window = \"$window\", action = \"toggle\" })" togglefloating "$window"
  hypr_dispatch "hl.dsp.window.resize({ window = \"$window\", x = $width, y = $height })" resizeactive exact "$width" "$height" "$window"

  if [[ -n $x && -n $y ]]; then
    hypr_dispatch "hl.dsp.window.move({ window = \"$window\", x = $x, y = $y })" moveactive "$x" "$y" "$window"
  else
    hypr_dispatch "hl.dsp.window.center({ window = \"$window\" })" centerwindow "$window"
  fi

  hypr_dispatch "hl.dsp.window.pin({ window = \"$window\" })" pin "$window"
  hypr_dispatch "hl.dsp.window.alter_zorder({ window = \"$window\", mode = \"top\" })" alterzorder top "$window"
  hypr_dispatch "hl.dsp.window.tag({ window = \"$window\", tag = \"+pop\" })" tagwindow +pop "$window"
fi
