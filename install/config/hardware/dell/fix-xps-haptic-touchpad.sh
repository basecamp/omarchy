# Fix Dell XPS haptic touchpad losing haptic feedback after suspend/resume.
# The I2C controller's runtime power management aggressively suspends the touchpad,
# and on resume the haptic engine sometimes fails to reinitialize.
# This udev rule keeps the I2C controller always on to prevent that.
# Applies to any Dell XPS with the Synaptics haptic touchpad (06CB:D01A).

if cat /sys/class/dmi/id/product_name 2>/dev/null | grep -qi "XPS" \
  && ls /sys/bus/i2c/devices/i2c-VEN_06CB:00 2>/dev/null; then

  # Disable runtime PM for I2C controller so haptic state isn't lost
  sudo tee /etc/udev/rules.d/99-dell-xps-haptic-touchpad.rules << 'EOF'
ACTION=="add", SUBSYSTEM=="pci", KERNEL=="0000:00:19.0", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="platform", KERNEL=="i2c_designware.0", ATTR{power/control}="on"
EOF
  sudo udevadm control --reload-rules

  # Rebind the I2C HID touchpad on boot and resume to reinitialize haptic engine
  sudo tee /etc/systemd/system/dell-xps-haptic-touchpad.service << 'SVC'
[Unit]
Description=Rebind Dell XPS haptic touchpad
After=systemd-udev-settle.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'if [[ -d /sys/bus/i2c/devices/i2c-VEN_06CB:00 ]]; then echo "i2c-VEN_06CB:00" | tee /sys/bus/i2c/drivers/i2c_hid_acpi/unbind > /dev/null 2>&1; sleep 1; echo "i2c-VEN_06CB:00" | tee /sys/bus/i2c/drivers/i2c_hid_acpi/bind > /dev/null 2>&1; fi'

[Install]
WantedBy=multi-user.target suspend.target hibernate.target
SVC
  sudo systemctl daemon-reload
  sudo systemctl enable dell-xps-haptic-touchpad.service
fi
