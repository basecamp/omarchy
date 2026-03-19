# Fix Dell XPS haptic touchpad losing haptic feedback after suspend/resume.
# The I2C controller's runtime power management aggressively suspends the touchpad,
# and on resume the haptic engine sometimes fails to reinitialize.
# This udev rule keeps the I2C controller always on to prevent that.
# Applies to any Dell XPS with the Synaptics haptic touchpad (06CB:D01A).

if cat /sys/class/dmi/id/product_name 2>/dev/null | grep -qi "XPS" \
  && ls /sys/bus/i2c/devices/i2c-VEN_06CB:00 2>/dev/null; then
  sudo tee /etc/udev/rules.d/99-dell-xps-haptic-touchpad.rules << 'EOF'
# Disable runtime PM for I2C controller to prevent haptic touchpad losing feedback after suspend
ACTION=="add", SUBSYSTEM=="pci", KERNEL=="0000:00:19.0", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="platform", KERNEL=="i2c_designware.0", ATTR{power/control}="on"
EOF
  sudo udevadm control --reload-rules
  sudo udevadm trigger --subsystem-match=pci --attr-match=device=0x00:19.0 2>/dev/null
fi
