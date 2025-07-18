#!/bin/bash

# Test script for styled power menu

# Menu options with invisible sort keys
menu_options="\u200B 󰌾  Lock
\u200C 󰤄  Suspend
\u200D 󰑓  Relaunch
\u2060 󰜉  Restart
\u2063 󰐥  Shutdown"

# Display with fuzzel using select.ini config (no prompt)
echo -e "$menu_options" | fuzzel --dmenu --prompt="" --config ~/.config/fuzzel/select.ini