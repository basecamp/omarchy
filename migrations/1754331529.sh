echo "Update Waybar for new Omarchy menu"

if ! grep -q ""; then
  omarchy-refresh-waybar
fi
