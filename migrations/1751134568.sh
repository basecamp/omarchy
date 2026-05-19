# Turn on bluetooth service so blueberry works out the box
echo "Let's turn on Bluetooth service so the controls work"
if systemctl is-enabled --quiet bluetooth.service && systemctl is-active --quiet bluetooth.service; then
  # Bluetooth is already enabled, nothing to change
  :
else
  sudo systemctl enable --now bluetooth.service
fi
