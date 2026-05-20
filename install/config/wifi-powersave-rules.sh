# The udev rule (/etc/udev/rules.d/99-omarchy-wifi-powersave.rules) ships via
# omarchy-settings. This script just reloads udev so the rule takes effect
# without waiting for a reboot.
# Also remove the pre-rename legacy path in case the old installer ran since
# the one-shot migration completed (idempotency for re-install/downgrade tests).
sudo rm -f /etc/udev/rules.d/99-wifi-powersave.rules
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=power_supply
