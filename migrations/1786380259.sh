echo "Remember Bluetooth on and off through the rfkill soft block"

marker="${OMARCHY_BLUETOOTH_MIGRATION_MARKER:-/var/lib/omarchy/migrations/1786380259}"
main_conf="${OMARCHY_BLUETOOTH_MAIN_CONF:-/etc/bluetooth/main.conf}"

# Machine-wide work, but migration completion is recorded per user, so a second
# account would run it again and undo whatever an administrator changed in
# between. Written last, so an interrupted run is retried rather than skipped.
if [[ -e $marker ]]; then
  exit 0
fi

# Read the machine as it stands before anything below changes it. Powered is the
# only record of what the user chose, and with AutoEnable=false holding the
# adapter down at every boot, no daemon to ask means off is what they have been
# living with.
#
# sudo because this runs machine-wide and /dev/rfkill is only writable without it
# from an active graphical seat — an update over SSH would otherwise abort here,
# before the marker, and abort again on every retry.
if omarchy-bluetooth-power is-on; then
  sudo omarchy-bluetooth-power on
else
  sudo omarchy-bluetooth-power off
fi

# Omarchy set AutoEnable=false believing bluetoothd would then restore the last
# power state. It has no such behaviour, so all the flag ever did was keep
# Bluetooth off at every boot. Left in place it would also stop bluetoothd from
# powering the adapter up when the block above is lifted. Only the exact line
# Omarchy wrote is reverted, so a hand-edited opt-out survives.
if [[ -f $main_conf ]]; then
  sudo sed -i 's/^AutoEnable=false$/#AutoEnable=true/' "$main_conf"
fi

sudo install -Dm644 /dev/null "$marker"
