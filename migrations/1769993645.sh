#!/bin/bash

# reapply the current theme and restart hyprland to ensure the environment variables are set.
THEME_NAME_PATH="$HOME/.config/omarchy/current/theme.name"

if [[ -f $THEME_NAME_PATH ]]; then
  omarchy-theme-set "$(cat $THEME_NAME_PATH)"
  omarchy-restart-hyprctl
fi
