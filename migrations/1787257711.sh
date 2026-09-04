echo "Install MacBookPro13,1 audio and camera compatibility support"

compatibility_marker="${OMARCHY_MACBOOKPRO13_1_MIGRATION_MARKER:-/var/lib/omarchy/migrations/macbookpro13-1-compatibility}"

if omarchy-hw-match '^MacBookPro13,1$' && [[ ! -e $compatibility_marker ]]; then
  omarchy-pkg-add snd-hda-macbookpro-dkms facetimehd-dkms facetimehd-firmware
  omarchy-pkg-drop macbook12-spi-driver-dkms
  sudo limine-mkinitcpio
  omarchy-state set reboot-required
  sudo install -Dm644 /dev/null "$compatibility_marker"
fi
