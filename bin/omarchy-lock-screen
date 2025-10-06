#!/bin/bash

# Lock the screen
pidof hyprlock || hyprlock &

# Ensure 1password is locked
if pgrep -x "1password" >/dev/null; then
  1password --lock &
fi

# Avoid running screensaver when locked
pkill -f "alacritty --class Screensaver"
