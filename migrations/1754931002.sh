echo "Give space for the entire update-available icon to fit in the waybar"

if grep '""' ~/.config/waybar/config.jsonc; then
  sed -i 's/""/" "/' ~/.config/waybar/config.jsonc
  omarchy-restart-waybar
fi
