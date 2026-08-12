set -e

echo "Disable HDA powersave for MSI X370 GAMING PLUS boards with ALC892"

source "$OMARCHY_PATH/install/config/hardware/msi/fix-alc892-jack-hotplug.sh"

if [[ -f /etc/modprobe.d/90-snd-hda-intel-jackfix.conf ]]; then
  omarchy-state set reboot-required
fi
