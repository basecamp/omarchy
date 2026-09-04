# Recover Intel Bluetooth when an rfkill soft block interrupts the firmware load.
#
# omarchy-bluetooth-power holds the off state in the rfkill soft block because
# that is the half systemd-rfkill restores across reboots. On Intel CNVi adapters
# the restore happens early enough to land while btusb is still downloading the
# firmware: the device drops off the bus mid-transfer, the download fails with
# -19 (ENODEV) and hci0 is torn down, so the machine boots with no Bluetooth
# controller rather than one that is merely powered off.
#
#   Bluetooth: hci0: Found device firmware: intel/ibt-0040-0041.sfi
#   Bluetooth: hci0: Failed to send firmware data (-19)
#   Bluetooth: hci0: FW download error recovery failed (-19)
#
# Turning Bluetooth back on cannot recover from that on its own: power_on() lifts
# the block and waits for BlueZ to power an adapter that no longer exists, then
# falls back to a bluetoothctl power on that has no controller to address.
#
# So watch for the unblock and reload btusb when it leaves no adapter behind.

if omarchy-hw-intel-bluetooth; then
  sudo mkdir -p /etc/systemd/system /etc/udev/rules.d

  sudo tee /etc/systemd/system/omarchy-bluetooth-recover.service >/dev/null <<'UNIT'
[Unit]
Description=Recover the Bluetooth adapter after an rfkill unblock

[Service]
Type=oneshot
ExecStart=/usr/bin/omarchy-bluetooth-recover
UNIT

  sudo cp -f "$OMARCHY_PATH/default/udev/intel-bluetooth-recover.rules" \
    /etc/udev/rules.d/90-omarchy-bluetooth-recover.rules

  sudo systemctl daemon-reload
  sudo udevadm control --reload-rules
fi
