sudo cp "$OMARCHY_PATH/default/udev/99-omarchy-platform-profile.rules" /etc/udev/rules.d/

sudo udevadm control --reload-rules
sudo udevadm trigger --action=add --subsystem-match=platform-profile
