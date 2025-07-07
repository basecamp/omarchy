#!/bin/bash

# Power menu for Omarchy
# Provides power off, restart, and sleep options

# Function to show power menu
show_power_menu() {
  local menu_options="\u200B Lock
\u200C󰤄 Sleep
\u200D Relaunch
\u2060󰜉 Restart
󰐥\u2063 Shutdown" # These first characters are invisible sort keys

  local selection=$(echo -e "$menu_options" | wofi --show dmenu --prompt "Power Options" --width 200 --height 250 -O alphabetical)

  case "$selection" in
  *Lock*) hyprlock ;;
  *Sleep*) systemctl suspend ;;
  *Relaunch*) hyprctl dispatch exit ;;
  *Restart*) systemctl reboot ;;
  *Shutdown*) systemctl poweroff ;;
  esac
}

# Main execution
show_power_menu
