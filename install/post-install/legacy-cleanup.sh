# Remove legacy paths replaced by package-owned Omarchy defaults.
rm -f /etc/udev/rules.d/99-power-profile.rules
rm -f /etc/udev/rules.d/99-wifi-powersave.rules
rm -f /etc/systemd/system.conf.d/99-omarchy-nofile.conf
rm -f /etc/systemd/user.conf.d/99-omarchy-nofile.conf
