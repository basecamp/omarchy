# Fix Dell XPS haptic touchpad.
# The Synaptics haptic touchpad (vendor 06CB) uses the HID Manual Trigger
# protocol, but the kernel's HID haptic subsystem only supports Auto Trigger.
# This sets up a lightweight daemon that monitors touchpad button events and
# sends haptic pulses via HID feature reports on the hidraw device.
# Also disables I2C runtime PM to prevent the haptic engine losing state
# across suspend/resume.

if omarchy-hw-dell-xps-haptic-touchpad; then

  # Keep I2C controller power on to prevent haptic engine losing state
  sudo tee /etc/udev/rules.d/99-dell-xps-haptic-touchpad.rules << 'EOF'
ACTION=="add", SUBSYSTEM=="pci", KERNEL=="0000:00:19.0", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="platform", KERNEL=="i2c_designware.0", ATTR{power/control}="on"
EOF
  sudo udevadm control --reload-rules

  # Haptic feedback daemon as a systemd service
  sudo tee /etc/systemd/system/dell-xps-haptic-touchpad.service << SVC
[Unit]
Description=Dell XPS haptic touchpad feedback
After=systemd-udev-settle.service

[Service]
Type=simple
EnvironmentFile=-/etc/omarchy-dell-haptic-touchpad.env
ExecStart=$OMARCHY_PATH/bin/omarchy-haptic-touchpad
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
SVC
  sudo systemctl daemon-reload
  sudo systemctl enable dell-xps-haptic-touchpad.service
fi
