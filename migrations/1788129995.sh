echo "Install Keychron udev rule for theme keyboard RGB sync"

if omarchy-hw-keychron && [[ ! -f /etc/udev/rules.d/50-keychron-rgb.rules ]]; then
  sudo mkdir -p /etc/udev/rules.d
  sudo cp -f "$OMARCHY_PATH/default/udev/keychron-rgb.rules" /etc/udev/rules.d/50-keychron-rgb.rules
fi
