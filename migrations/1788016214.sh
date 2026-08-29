echo "Load I2C-HID internal keyboard modules into the boot image"

# Laptops whose internal keyboard sits on the I2C-HID bus (e.g. ASUS ExpertBook
# B3402FBA) have no working keyboard at the LUKS passphrase prompt: mkinitcpio's
# keyboard hook collects USB and PS/2 drivers, but its '/hid/hid' glob misses
# drivers/hid/i2c-hid/, and the I2C controller (drivers/mfd/) and GPIO pinctrl
# (drivers/pinctrl/) modules the bus depends on are never pulled in either.
# New installs get the module list from install/hardware/fix-i2c-hid-keyboard.sh;
# this repairs existing machines and rebuilds the boot image.

conf="${OMARCHY_I2C_HID_KEYBOARD_CONF:-/etc/mkinitcpio.conf.d/i2c_hid_keyboard_modules.conf}"

omarchy-hw-i2c-hid-keyboard || exit 0

# The conf doubles as the machine-wide marker: another user's migration run
# must not repeat the rebuild once the modules are in place.
[[ ! -f $conf ]] || exit 0

omarchy-cmd-present limine-mkinitcpio || exit 0

modules=(i2c_hid i2c_hid_acpi hid_multitouch)

# The I2C controller and GPIO interrupt drivers differ per platform
# (pinctrl_tigerlake, pinctrl_alderlake, pinctrl_amd, ...), so collect
# whatever the running system loaded, same as the Surface keyboard fix.
for module in $(lsmod | awk '$1 ~ /^(pinctrl_|intel_lpss)/ { print $1 }'); do
  modules+=("$module")
done

sudo mkdir -p /etc/mkinitcpio.conf.d
printf 'MODULES+=(%s)\n' "${modules[*]}" | sudo tee "$conf" >/dev/null
sudo limine-mkinitcpio
