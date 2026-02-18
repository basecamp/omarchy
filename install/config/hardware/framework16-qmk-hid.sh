# Allow unprivileged access to the Framework 16 keyboard for RGB control via qmk_hid.

if omarchy-hw-framework16; then
  if [[ ! -f /etc/udev/rules.d/50-framework16-qmk-hid.rules ]]; then
    sudo cp "$OMARCHY_PATH/default/udev/framework16-qmk-hid.rules" /etc/udev/rules.d/50-framework16-qmk-hid.rules
    sudo udevadm control --reload-rules
    sudo udevadm trigger
  fi
fi
