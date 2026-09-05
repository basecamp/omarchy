# Allow unprivileged access to Keychron keyboards for RGB control and Keychron Launcher.

if omarchy-hw-keychron; then
  sudo mkdir -p /etc/udev/rules.d
  if [[ ! -f /etc/udev/rules.d/50-keychron-rgb.rules ]]; then
    sudo cp -f "$OMARCHY_PATH/default/udev/keychron-rgb.rules" /etc/udev/rules.d/50-keychron-rgb.rules
  fi
fi
