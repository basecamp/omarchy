echo "Lock 1password on screen lock"

if ! grep -q "omarchy-lock-screen" ~/.config/hypr/hypridle.conf; then
  omarchy-refresh-hypridle
fi
