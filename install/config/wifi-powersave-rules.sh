# Remove the pre-rename legacy path on every run (idempotent vs the one-shot
# migration, which only fires once per user).
sudo rm -f /etc/udev/rules.d/99-wifi-powersave.rules
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=power_supply
