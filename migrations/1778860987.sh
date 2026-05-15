echo "Install rotating backgrounds systemd timer"

mkdir -p ~/.config/systemd/user
cp "$OMARCHY_PATH/config/systemd/user/omarchy-bg-cycle.service" ~/.config/systemd/user/omarchy-bg-cycle.service
cp "$OMARCHY_PATH/config/systemd/user/omarchy-bg-cycle.timer" ~/.config/systemd/user/omarchy-bg-cycle.timer

systemctl --user daemon-reload
