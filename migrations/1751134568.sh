# Turn on bluetooth service so blueberry works out the box
if systemctl is-enabled --quiet bluetooth.service && systemctl is-active --quiet bluetooth.service; then
  # Bluetooth is already enabled, nothing to change
  :
else
  echo "Let's turn on Bluetooth service so the controls work"
  sudo systemctl enable --now bluetooth.service
fi
