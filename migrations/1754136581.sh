echo "Start screensaver automatically after 1 minute and stop before locking"

if ! grep -q "omarchy-launch-screensaver" ~/.config/hypr/hypridle.conf; then
  omarchy-refresh-hypridle
  omarchy-refresh-hyprlock
fi
