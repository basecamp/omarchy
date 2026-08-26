echo "Save and restore Apple GMUX backlight brightness across reboot"

# Dual-GPU Macs expose the panel as gmux_backlight on the PNP bus. systemd's
# path_id builtin fails there, so 99-systemd.rules never starts
# systemd-backlight and brightness resets to the firmware default after reboot.
# See install/hardware/apple/fix-gmux-backlight.sh.
source "$OMARCHY_PATH/install/hardware/apple/fix-gmux-backlight.sh"
