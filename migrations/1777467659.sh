echo "Rename lock screen command in Hypridle config"

if grep -q 'omarchy-lock-screen' ~/.config/hypr/hypridle.conf; then
  sed -i 's/omarchy-lock-screen/omarchy-system-lock/g' ~/.config/hypr/hypridle.conf
  omarchy-restart-hypridle
fi
