set -e

echo "Install nuphyctl-bin and udev rule on systems with a NuPhy keyboard"

if omarchy-hw-nuphyio-keyboard; then
  if omarchy-pkg-missing nuphyctl-bin; then
    omarchy-pkg-aur-add nuphyctl-bin
  fi
  if [[ ! -f /etc/udev/rules.d/50-nuphyio.rules ]]; then
    sudo cp "$OMARCHY_PATH/default/udev/nuphyio.rules" /etc/udev/rules.d/50-nuphyio.rules
    sudo udevadm control --reload-rules
    sudo udevadm trigger
  fi
fi
