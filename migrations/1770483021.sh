echo "Install Framework 16 keyboard RGB support"

if omarchy-hw-framework16; then
  omarchy-pkg-add qmk-hid

  if [[ ! -f /etc/udev/rules.d/50-framework16-qmk-hid.rules ]]; then
    sudo cp "$OMARCHY_PATH/default/udev/framework16-qmk-hid.rules" /etc/udev/rules.d/50-framework16-qmk-hid.rules
    sudo udevadm control --reload-rules
    sudo udevadm trigger
  fi
fi
