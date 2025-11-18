#!/bin/bash

# Toggle to pop-out a tile to stay fixed on a display basis.

# Usage:
# omarchy-hyprland-window-pop [WIDTH HEIGHT [X Y]]
#
# Arguments:
#   WIDTH   Optional. Width of the floating window. Default: 1300
#   HEIGHT  Optional. Height of the floating window. Default: 900
#   X       Optional. X position of the window. Must provide both X and Y to take effect.
#   Y       Optional. Y position of the window. Must provide both X and Y to take effect.
#
# Behavior:
#   - If the window is already pinned, it will be unpinned and removed from the pop layer.
#   - If the window is not pinned, it will be floated, resized, moved/centered, pinned, brought to top, and popped.

WIDTH=${1:-1300}
HEIGHT=${2:-900}
X=${3:-}
Y=${4:-}

active=$(hyprctl activewindow -j)
pinned=$(echo "$active" | jq ".pinned")
addr=$(echo "$active" | jq -r ".address")

[ -z "$addr" ] && {
  echo "No active window"
  exit 0
}

if [ "$pinned" = "true" ]; then
  hyprctl -q --batch \
    "dispatch pin address:$addr;" \
    "dispatch togglefloating address:$addr;" \
    "dispatch tagwindow -pop address:$addr;"
else
  hyprctl dispatch togglefloating address:"$addr"
  hyprctl dispatch resizeactive exact "$WIDTH" "$HEIGHT" address:"$addr"

  if [[ -n "$X" && -n "$Y" ]]; then
    hyprctl dispatch moveactive "$X" "$Y" address:"$addr"
  else
    hyprctl dispatch centerwindow address:"$addr"

  fi

  hyprctl -q --batch \
    "dispatch pin address:$addr;" \
    "dispatch alterzorder top address:$addr;" \
    "dispatch tagwindow +pop address:$addr;"
fi
