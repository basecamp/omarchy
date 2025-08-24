echo "Add status indicators for nightlight, dnd, and idle lock to Waybar"
echo
gum confirm "Replace current Waybar config (backup will be made)?" && omarchy-refresh-waybar
