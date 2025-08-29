echo "Update Omarchy icon font and rebuild font cache"

mkdir -p ~/.local/share/fonts
cp ~/.local/share/omarchy/config/omarchy.ttf ~/.local/share/fonts/
fc-cache
omarchy-refresh-waybar
