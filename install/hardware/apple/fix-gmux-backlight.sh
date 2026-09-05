# Persist panel brightness on Macs whose backlight is apple-gmux.
#
# systemd-backlight never attaches to gmux_backlight: udev path_id cannot
# name the PNP bus, so 99-systemd.rules skips SYSTEMD_WANTS. Drop a rule
# that does not import path_id. Keyboard backlight is on PCI/SPI and is
# already persisted by stock systemd.

if omarchy-hw-apple-gmux; then
  echo "Detected apple-gmux panel backlight"

  # shellcheck source=gmux-backlight.sh
  source "$OMARCHY_INSTALL/hardware/apple/gmux-backlight.sh"

  gmux_install_rule
  gmux_activate
fi
