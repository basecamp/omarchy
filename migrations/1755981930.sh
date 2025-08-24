echo "Add Omarchy icon to the Waybar"

mkdir -p ~/.local/share/fonts
cp ~/.local/share/omarchy/config/omarchy.ttf ~/.local/share/fonts/
fc-cache

echo
gum confirm "Replace current Waybar config (backup will be made)?" && omarchy-refresh-waybar

