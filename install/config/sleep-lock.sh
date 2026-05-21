mkdir -p ~/.config/systemd/user/
cp "$OMARCHY_PATH/config/systemd/user/omarchy-sleep-lock.service" ~/.config/systemd/user/
systemctl --user enable omarchy-sleep-lock.service
