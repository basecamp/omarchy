# The udev rule (/etc/udev/rules.d/99-omarchy-wifi-powersave.rules) ships via
# omarchy-settings. This script just reloads udev so the rule takes effect
# without waiting for a reboot.
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=power_supply
