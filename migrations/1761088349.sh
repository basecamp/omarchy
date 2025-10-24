#!/bin/bash
echo "Setting up ddcutil for external monitor brightness"
omarchy-pkg-add ddcutil
if omarchy-pkg-present ddcutil; then
  sudo modprobe i2c-dev
  echo 'i2c-dev' | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
  sudo gpasswd -a "$USER" i2c
fi
