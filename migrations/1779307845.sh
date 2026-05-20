echo "Clean up legacy udev rules now namespaced under 99-omarchy-*.rules"

# powerprofilesctl-rules.sh used to write /etc/udev/rules.d/99-power-profile.rules.
# Package now ships /etc/udev/rules.d/99-omarchy-power-profile.rules. Both
# rules would fire simultaneously, so remove the old one.
sudo rm -f /etc/udev/rules.d/99-power-profile.rules

# wifi-powersave-rules.sh used to write /etc/udev/rules.d/99-wifi-powersave.rules.
# Package now ships /etc/udev/rules.d/99-omarchy-wifi-powersave.rules. Same.
sudo rm -f /etc/udev/rules.d/99-wifi-powersave.rules

# Reload so the new rules take effect immediately.
sudo udevadm control --reload 2>/dev/null
sudo udevadm trigger --subsystem-match=power_supply 2>/dev/null
