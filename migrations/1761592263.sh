#!/usr/bin/env bash
echo "Replace Impala with Gazelle"

omarchy-pkg-drop impala

if omarchy-cmd-missing gazelle; then
  omarchy-pkg-add gazelle-tui
fi

omarchy-restart-waybar
