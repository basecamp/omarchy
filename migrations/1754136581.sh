echo "Start screensaver automatically after 1 minute"

if ! grep -q "omarchy-launch-screensaver" ~/.config/hypr/hypridle.conf; then
  omarchy-refresh-hypridle
fi
