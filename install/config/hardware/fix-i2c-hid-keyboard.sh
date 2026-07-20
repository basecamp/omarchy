# Detect laptops with I2C HID built-in keyboards that require i2c_hid modules
# in the initramfs to function at the LUKS passphrase prompt (Plymouth).
# The standard `keyboard` mkinitcpio hook only bundles PS/2 and USB HID drivers.
if find /sys/bus/i2c/drivers/i2c_hid_acpi -maxdepth 1 -name 'i2c-*' 2>/dev/null | grep -q .; then
  echo "Detected I2C HID keyboard, adding i2c_hid modules to initramfs"
  echo "MODULES=(i2c_hid i2c_hid_acpi)" | sudo tee /etc/mkinitcpio.conf.d/i2c_hid_keyboard.conf >/dev/null
fi
