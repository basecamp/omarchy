# Allow unprivileged access to NuPhy keyboards for RGB control via nuphyctl.

if omarchy-hw-nuphyio-keyboard; then
  if [[ ! -f /etc/udev/rules.d/50-nuphyio.rules ]]; then
    sudo cp "$OMARCHY_PATH/default/udev/nuphyio.rules" /etc/udev/rules.d/50-nuphyio.rules
    sudo udevadm control --reload-rules
    sudo udevadm trigger
  fi
fi
