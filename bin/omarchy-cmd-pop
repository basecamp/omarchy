#!/bin/bash

# Toggle to pop-out a tile to stay fixed on a display basis.

active=$(hyprctl activewindow -j)
pinned=$(echo "$active" | jq .pinned)
addr=$(echo "$active" | jq -r  ".address")
[ -z "$addr" ] && { echo "No active window"; exit 0; }

if [ "$pinned" = "true" ]; then
  hyprctl -q --batch \
  "dispatch pin address:$addr;" \
  "dispatch togglefloating address:$addr;" \
  "dispatch tagwindow -pop address:$addr;"
else
  hyprctl -q --batch \
  "dispatch togglefloating address:$addr;" \
  "dispatch centerwindow address:$addr;" \
  "dispatch pin address:$addr;" \
  "dispatch alterzorder top address:$addr;" \
  "dispatch tagwindow +pop address:$addr;"
fi
