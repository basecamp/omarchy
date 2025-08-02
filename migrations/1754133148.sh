echo "Update Waybar CSS to dim unused workspaces"

if ! grep -q "#workspaces button\.empty" ~/.config/waybar/style.css; then
  omarchy-refresh-config waybar/style.css
  pkill -SIGUSR2 waybar
fi
