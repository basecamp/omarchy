echo "Show OSD when the ACPI platform profile changes"

mkdir -p ~/.config/systemd/user
cp -f $OMARCHY_PATH/config/systemd/user/omarchy-powerprofiles-osd.service ~/.config/systemd/user/omarchy-powerprofiles-osd.service
systemctl --user daemon-reload
systemctl --user enable --now omarchy-powerprofiles-osd.service
