# The udev rule (/etc/udev/rules.d/99-omarchy-power-profile.rules) ships via
# omarchy-settings. This script handles the runtime side: enable the service
# the rule's RUN+= chains through, and reload udev so the new rule takes effect.
sudo systemctl enable power-profiles-daemon
sudo udevadm control --reload 2>/dev/null
sudo udevadm trigger --subsystem-match=power_supply 2>/dev/null
