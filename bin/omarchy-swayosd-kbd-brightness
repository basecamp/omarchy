#!/bin/bash

# Display keyboard brightness level using SwayOSD on the current monitor.
# Usage: omarchy-swayosd-kbd-brightness <percent>

percent="$1"

progress="$(awk -v p="$percent" 'BEGIN{printf "%.2f", p/100}')"
[[ $progress == "0.00" ]] && progress="0.01"

swayosd-client \
  --monitor "$(hyprctl monitors -j | jq -r '.[]|select(.focused==true).name')" \
  --custom-icon keyboard-brightness \
  --custom-progress "$progress" \
  --custom-progress-text "${percent}%"
