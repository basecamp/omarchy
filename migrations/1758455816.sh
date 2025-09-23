echo "Add relaunch-required and reboot-required indicator to waybar"

gum confirm "Replace current Waybar config (backup will be made)?" && omarchy-refresh-waybar
