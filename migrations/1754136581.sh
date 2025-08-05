echo "Start screensaver automatically after 1 minute and stop before locking"

if ! grep -q "omarchy-launch-screensaver" ~/.config/hypr/hypridle.conf; then
  ~/.local/share/omarchy/bin/omarchy-refresh-hypridle
  ~/.local/share/omarchy/bin/omarchy-refresh-hyprlock
fi
