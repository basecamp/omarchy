#!/bin/bash

# Fix screenshot regression with hyprpicker on HDR displays
# See: https://github.com/basecamp/omarchy/issues/5376

echo "Adding screenshot HDR fix"

# Backup existing screenshot script
if [[ -f ~/.local/share/omarchy/bin/omarchy-cmd-screenshot ]]; then
  cp ~/.local/share/omarchy/bin/omarchy-cmd-screenshot ~/.local/share/omarchy/bin/omarchy-cmd-screenshot.bak
fi

# The fix adds wayfreeze fallback for HDR displays where hyprpicker causes color issues
# wayfreeze was removed in migration 1762156000, but it may still be needed for HDR compatibility
# This migration reinstalls wayfreeze for users who need it

if ! omarchy-cmd-present wayfreeze; then
  if gum confirm "Install wayfreeze for better HDR screenshot support?"; then
    omarchy-pkg-add wayfreeze
  fi
fi

notify-send "Screenshot HDR fix applied" "Restart Hyprland to apply changes"
