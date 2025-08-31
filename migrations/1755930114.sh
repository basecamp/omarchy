echo "Add new Omarchy Menu icon to Waybar"

mkdir -p ~/.local/share/fonts
cp ~/.local/share/omarchy/config/omarchy.ttf ~/.local/share/fonts/
fc-cache

echo
omarchy-confirm "Replace current Waybar config (backup will be made)?" && omarchy-refresh-waybar
