echo "Move idle handling from hypridle to omarchy-shell"

if [[ -f ~/.config/hypr/autostart.lua ]]; then
  sed -i '/hypridle/d' ~/.config/hypr/autostart.lua
fi

omarchy-refresh-shell
pkill -x hypridle 2>/dev/null || true
omarchy-pkg-drop hypridle
omarchy-restart-shell || true
