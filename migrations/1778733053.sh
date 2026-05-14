#!/bin/bash

# Enable the theme scheduler timer if it was recently added
if [[ -f "$HOME/.config/systemd/user/omarchy-theme-schedule.timer" ]]; then
  systemctl --user enable --now omarchy-theme-schedule.timer || true
fi
