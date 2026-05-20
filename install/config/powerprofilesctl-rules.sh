# The udev rule (/etc/udev/rules.d/99-omarchy-power-profile.rules) ships via
# omarchy-settings. power-profiles-daemon.service enable lives in
# install/config/enable-services.sh. This script just reloads udev so the
# rule takes effect and removes the pre-rename legacy path (idempotent for
# re-install/downgrade tests).
sudo rm -f /etc/udev/rules.d/99-power-profile.rules
sudo udevadm control --reload 2>/dev/null
sudo udevadm trigger --subsystem-match=power_supply 2>/dev/null
