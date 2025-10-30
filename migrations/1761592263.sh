#!/usr/bin/env bash
echo "Replace Impala with Gazelle"

omarchy-pkg-drop impala

if omarchy-cmd-missing gazelle; then
  yay -S --noconfirm gazelle-tui
  omarchy-restart-waybar
fi

