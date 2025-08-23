echo "Add Omarchy icon to the Waybar"

cp ~/.local/share/omarchy/config/omarchy.ttf /usr/share/fonts/

echo
gum confirm "Replace current Waybar config (backup will be made)?" && omarchy-refresh-waybar

