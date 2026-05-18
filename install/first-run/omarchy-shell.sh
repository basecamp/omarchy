mkdir -p ~/.config/systemd/user
cp "$OMARCHY_PATH/config/systemd/user/omarchy-shell.service" ~/.config/systemd/user/omarchy-shell.service
systemctl --user daemon-reload
systemctl --user enable --now omarchy-shell.service
