set -e

echo "Install ddcutil for DDC brightness fallback"

if omarchy-pkg-missing ddcutil; then
  omarchy-pkg-add ddcutil
fi

# ddcutil ships /usr/lib/modules-load.d/ddcutil.conf and
# /usr/lib/udev/rules.d/60-ddcutil-i2c.rules. Load the module now so the
# current session can use DDC without a reboot, and re-run udev so the
# upstream uaccess rule applies to already-enumerated i2c-dev buses.
sudo modprobe i2c-dev
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=i2c-dev
