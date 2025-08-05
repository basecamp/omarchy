echo "Ensure screensaver doesn't start while the computer is locked"

if ! grep -q "pidof hyprlock || omarchy-launch-screensaver" ~/.config/hypr/hypridle.conf; then
  ~/.local/share/omarchy/bin/omarchy-refresh-hypridle
fi
