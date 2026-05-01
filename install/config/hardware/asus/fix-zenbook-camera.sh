if omarchy-hw-match "Zenbook"; then
  sudo tee /etc/sudoers.d/omarchy-camera-zenbook << EOF
$USER ALL=(root) NOPASSWD: /usr/bin/tee /sys/bus/usb/drivers/usb/bind, /usr/bin/tee /sys/bus/usb/drivers/usb/unbind
EOF
  sudo chmod 440 /etc/sudoers.d/omarchy-camera-zenbook
fi
