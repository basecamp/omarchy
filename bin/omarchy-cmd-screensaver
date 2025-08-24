#!/bin/bash

while true; do
  effect=$(tte 2>&1 | grep -oP '{\K[^}]+' | tr ',' ' ' | tr ' ' '\n' | sed -n '/^beams$/,$p' | sort -u | shuf -n1)
  tte -i ~/.config/omarchy/branding/screensaver.txt \
    --frame-rate 240 --canvas-width 0 --canvas-height $(($(tput lines) - 2)) --anchor-canvas c --anchor-text c \
    "$effect" &

  while pgrep -x tte >/dev/null; do
    if read -n 1 -t 0.01; then
      pkill -x tte 2>/dev/null
      pkill -f "alacritty --class Screensaver" 2>/dev/null
      exit 0
    fi
  done
done
