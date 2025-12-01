#!/bin/bash

# Default temperature values
ON_TEMP=4000
OFF_TEMP=6000

# Ensure hyprsunset is running
if ! pgrep -x hyprsunset; then
  setsid uwsm-app -- hyprsunset &
  sleep 1 # Give it time to register
fi

# Query the current temperature
CURRENT_TEMP=$(hyprctl hyprsunset temperature 2>/dev/null | grep -oE '[0-9]+')

restart_nightlighted_waybar() {
  if grep -q "custom/nightlight" ~/.config/waybar/config.jsonc; then
    omarchy-restart-waybar # restart waybar in case user has waybar module for hyprsunset
  fi
}

if [[ "$CURRENT_TEMP" == "$OFF_TEMP" ]]; then
  hyprctl hyprsunset temperature $ON_TEMP
  notify-send "  Nightlight screen temperature"
  restart_nightlighted_waybar
else
  hyprctl hyprsunset temperature $OFF_TEMP
  notify-send "   Daylight screen temperature"
  restart_nightlighted_waybar
fi
