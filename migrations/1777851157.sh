echo "Ensure Dell XPS touchpad haptics comes from the packaged service"

if omarchy-hw-dell-xps-haptic-touchpad; then
  sudo systemctl disable --now dell-xps-haptic-touchpad.service 2>/dev/null || true
  sudo rm -f /etc/systemd/system/dell-xps-haptic-touchpad.service
  sudo rm -f /etc/systemd/system/multi-user.target.wants/dell-xps-haptic-touchpad.service
  sudo rm -rf /etc/systemd/system/dell-xps-haptic-touchpad.service.d
  sudo rm -f /etc/udev/rules.d/99-dell-xps-haptic-touchpad.rules
  sudo rm -f /etc/omarchy-dell-haptic-touchpad.env
  sudo systemctl daemon-reload
  sudo udevadm control --reload-rules

  source "$OMARCHY_PATH/install/packaging/dell-xps-touchpad-haptics.sh"
  sudo systemctl enable --now dell-xps-touchpad-haptics.service 2>/dev/null || true
fi
