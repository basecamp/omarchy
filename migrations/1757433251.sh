#!/bin/bash

# Add wallpaper rotation feature for existing users
if [[ ! -f ~/.config/systemd/user/omarchy-wallpaper-rotation.timer ]]; then
  # Copy systemd files to user config
  cp ~/.local/share/omarchy/config/systemd/user/omarchy-wallpaper-rotation.* ~/.config/systemd/user/
  
  # Reload systemd user daemon
  systemctl --user daemon-reload
  
  # Don't enable by default - let users opt-in via menu
  notify-send "New Feature" "Wallpaper auto-rotation available in Toggle and Style menus" -t 3000
fi