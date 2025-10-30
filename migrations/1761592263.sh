#!/usr/bin/env bash
echo "Replace Impala with Gazelle"

omarchy-pkg-drop impala

if omarchy-cmd-missing gazelle; then
  yay -S --noconfirm gazelle-tui
fi

omarchy-restart-waybar
