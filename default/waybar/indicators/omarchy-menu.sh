#!/usr/bin/env bash
# Outputs JSON for Waybar
keybind="$($OMARCHY_PATH/bin/omarchy-keybinding omarchy-menu)"
echo "{\"text\": \"<span font='omarchy'>\ue900</span>\", \"tooltip\": \"Omarchy Menu\n\n${keybind}\"}"
