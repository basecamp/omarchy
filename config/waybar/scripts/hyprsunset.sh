#!/bin/bash

# default temperature values
ON_TEMP=4000
OFF_TEMP=6000

# ensure hyprsunset is running
if ! pgrep -x hyprsunset >/dev/null; then
  setsid uwsm app -- hyprsunset &
  sleep 1 # give it time to register
fi

# handle click events from waybar
if [[ "$1" == "toggle" ]]; then
  CURRENT_TEMP=$(hyprctl hyprsunset temperature 2>/dev/null | grep -oE '[0-9]+')
  if [[ "$CURRENT_TEMP" == "$OFF_TEMP" ]]; then
    hyprctl hyprsunset temperature $ON_TEMP
    notify-send " Nightlight screen temperature"
  else
    hyprctl hyprsunset temperature $OFF_TEMP
    notify-send "  Daylight screen temperature"
  fi
  # restart waybar if necessary
  if grep -q "custom/nightlight" ~/.config/waybar/config.jsonc; then
    omarchy-restart-waybar
  fi
fi

# get current temperature
CURRENT_TEMP=$(hyprctl hyprsunset temperature 2>/dev/null | grep -oE '[0-9]+' || echo "N/A")

# determine icon based on temperature
if [[ "$CURRENT_TEMP" == "$ON_TEMP" ]]; then
  ICON=""
  CLASS="nightlight-on"
elif [[ "$CURRENT_TEMP" == "$OFF_TEMP" ]]; then
  ICON=""
  CLASS="nightlight-off"
else
  ICON=""
  CLASS="nightlight-error"
fi

# output (JSON)
echo "{\"text\": \"$ICON\", \"class\": \"$CLASS\", \"tooltip\": \"Screen temperature: $CURRENT_TEMP K\"}"
