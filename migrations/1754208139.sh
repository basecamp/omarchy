echo "Ensure screensaver doesn't start while the computer is locked"

if ! grep -q "pidof hyprlock || omarchy-launch-screensaver" ~/.config/hypr/hypridle.conf; then
  omarchy-refresh-hypridle
fi
