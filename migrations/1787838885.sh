echo "Set up keyd for the Logitech MX Keys S action row"

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"

# Machine-wide and idempotent: skip once the config is in place AND the service
# is enabled, so a run that failed partway (config written, restart failed)
# still gets repaired on the next update.
[[ -f /etc/keyd/logitech-mx-keys.conf ]] && systemctl is-enabled --quiet keyd.service && exit 0

# Unprivileged pre-filter so machines with no Bolt receiver and no Bluetooth
# MX Keys S never reach the (password-prompting) hidraw probe.
grep -qEi 'HID_ID=0003:0000046D:0000C548|MX Keys S' \
  /sys/class/hidraw/*/device/uevent 2>/dev/null || exit 0

source "$OMARCHY_PATH/install/hardware/logitech-mx-keys.sh"
