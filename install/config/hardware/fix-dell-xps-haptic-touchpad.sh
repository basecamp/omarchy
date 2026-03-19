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

  # Rebind the I2C HID touchpad on resume to fully reinitialize haptic engine
  sudo tee /usr/lib/systemd/system-sleep/dell-xps-haptic-touchpad << 'HOOK'
#!/bin/bash
if [[ $1 == "post" ]]; then
  if [[ -d /sys/bus/i2c/devices/i2c-VEN_06CB:00 ]]; then
    echo "i2c-VEN_06CB:00" > /sys/bus/i2c/drivers/i2c_hid_acpi/unbind 2>/dev/null
    sleep 1
    echo "i2c-VEN_06CB:00" > /sys/bus/i2c/drivers/i2c_hid_acpi/bind 2>/dev/null
  fi
fi
HOOK
  sudo chmod +x /usr/lib/systemd/system-sleep/dell-xps-haptic-touchpad
fi
