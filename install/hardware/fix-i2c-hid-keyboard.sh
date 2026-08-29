# Laptops whose internal keyboard sits on the I2C-HID bus (e.g. ASUS ExpertBook
# B3402FBA) have no working keyboard at the LUKS passphrase prompt: mkinitcpio's
# keyboard hook collects USB and PS/2 drivers, but its '/hid/hid' glob misses
# drivers/hid/i2c-hid/, and the I2C controller (drivers/mfd/) and GPIO pinctrl
# (drivers/pinctrl/) modules the bus depends on are never pulled in either.
# List them explicitly so the initramfs can take the passphrase.

if omarchy-hw-i2c-hid-keyboard; then
  echo "Detected internal keyboard on I2C-HID"

  modules=(i2c_hid i2c_hid_acpi hid_multitouch)

  # The I2C controller and GPIO interrupt drivers differ per platform
  # (pinctrl_tigerlake, pinctrl_alderlake, pinctrl_amd, ...), so collect
  # whatever the running system loaded, same as the Surface keyboard fix.
  for module in $(lsmod | awk '$1 ~ /^(pinctrl_|intel_lpss)/ { print $1 }'); do
    modules+=("$module")
  done

  mkdir -p /etc/mkinitcpio.conf.d
  printf 'MODULES+=(%s)\n' "${modules[*]}" > /etc/mkinitcpio.conf.d/i2c_hid_keyboard_modules.conf
fi
